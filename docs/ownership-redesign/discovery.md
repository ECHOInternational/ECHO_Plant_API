# Ownership Redesign — Discovery Report

*Cross-repository audit for the organization-based ownership redesign. Verified 2026-07-13 against the four working trees. Companion current-state docs: `docs/ownership-current-state.md` (ownership mechanics, verified in detail) and `docs/authorization-trust-levels.md` (trust ladder). This report adds the cross-repo system map, contract inventory, and hazards. File references are repo-relative unless prefixed.*

---

## 1. System map

| Unit | Repo | Stack | Deploys | Can change? |
|---|---|---|---|---|
| Plant API | `ECHO_Plant_API` | Rails 8.1.3 / Ruby 3.4.10, PG (RDS), GraphQL 2.3.23, Pundit 2.5.2, PaperTrail 17, Mobility 1.2.9 (held) | ECS Fargate; GH Actions build→staging auto→prod manual gate; separate `-migrate` one-off task runs `db:migrate` | yes (primary) |
| IdP | `ECHOcommunity` | Rails 8.1.3 / Ruby 3.3.11, Devise + Doorkeeper 5.7.1 + doorkeeper-jwt + doorkeeper-openid_connect | ECS Fargate (`ECHOcommunity_Transition`), staged phases | yes, if required |
| Admin SPA | `plant_data_admin_interface` | React 19 / Vite, graphql-request + codegen | S3+CloudFront, push-to-main deploys **immediately** (no gate, no PR CI) | yes (lockstep with API) |
| Mobile app | `echocommunity-app` | RN 0.63.3, raw axios GraphQL (no client lib, no codegen), SQLite offline store | app stores; **only the external developer can release; slow** | **NO — hard compatibility contract** |

**Auth flow:** OAuth2 authorization-code at `www.echocommunity.org` (Doorkeeper; PKCE for SPA, client-secret flow in mobile WebView) → RS256 JWT access token (~2h, refresh tokens enabled) → Plant API verifies signature with the public key (`APPLICATION_JWT_SECRET`) and builds an in-memory `User` from the `user` claim (`app/controllers/application_controller.rb:22-45`). The API never issues tokens; there is no users table.

**Data flow:** No background jobs, no schedulers, no import/sync pipelines exist in the Plant API (Sidekiq absent; `development/data_transfer/` scripts are one-off exports from the old monolith; `db/seeds.rb` writes `owned_by: 'echo@echonet.org'`). The only writers are the two clients plus seeds.

**Other consumers found:** the SPA seed script (`scripts/seed-from-prod.ts`, anonymous reads of lookups + `createCategory`); curl examples in docs. The mobile app's separate "resources API" GraphQL at echocommunity.org is read-only, effectively unauthenticated, and out of scope. No persisted/whitelisted queries anywhere.

## 2. Current authorization map

- **Trust ladder** (JWT `user.trust_levels.plant`): `can_read?` ≥1, `can_write?` ≥2, `admin?` ≥9, `super_admin?` ≥10 (`app/models/user.rb`). IdP registration default is **plant: 2** (`ECHOcommunity app/models/user.rb:390-393`) — every echocommunity user can write. IdP labels level 8 "Administrator" but the API's `admin?` is >8 (known support trap).
- **`OwnedResourcePolicy`** (`app/policies/owned_resource_policy.rb`): `show?` = admin ∨ owner-email ∨ public; `create?` = can_write; `update?` = can_write ∧ (admin ∨ owner); `destroy?` = can_write ∧ (super_admin ∨ owner). Scope: admin → all; user → public ∪ own; anon → public. Inherited unchanged by Plant/Variety/Specimen/Location/Category policies.
- **Divergent policies:** `ImagePolicy` — effective two-owner union (imageable's owner ∨ image's own `owned_by` ∨ admin), `create?` hard-false (creation authorizes `update?` on the imageable). `LifeCycleEventPolicy` — delegates `update?` to the specimen; scope joins specimens. Lookups (Tolerance/GrowthHabit/Antinutrient/ImageAttribute) — public read, super-admin write. `UploadPolicy` — `can_write?`.
- **Non-Pundit authorization:** exactly one reproduction — `PlantType#policy_scope_loaded` (`app/graphql/types/plant_type.rb:227-236`), an in-Ruby mirror of the scope for the eager-loaded `varieties` association. Also `SpecimenType#life_cycle_events` returns the association unscoped (safe only because the parent specimen was already scoped).
- **Creation ownership:** every create mutation stamps `created_by` and `owned_by` from `context[:current_user].email`; never client-suppliable; never changeable afterwards; no transfer mechanism; creator ≡ owner always.
- **Deletion:** soft = `visibility: :deleted` via `SoftDeletePlant/Variety/Location` (authorize `:update?`, dependency check + `force`); restore = normal update to `PRIVATE` (prior state lost). Hard deletes exist for all six models (authorize `:destroy?`); `DeleteLifeCycleEvent` sets a **separate `deleted` boolean** on the event (not the enum). Specimen has hard delete only.

## 3. Contract inventory

**JWT claim shape** (issued in `ECHOcommunity config/initializers/doorkeeper.rb:37-63`): `iss: 'https://www.echocommunity.org'`, `aud` = OAuth app uid, `exp` ≈ 2h, and `user: { id: <int PK>, email, uid: <UUID string>, active_development_worker, allow_seed_bank_access, trust_levels: { general, curriculum, plant, resource_restrictions } }`. `users.uid` is UNIQUE-indexed, generated once at registration (`SecureRandom.uuid`), used as the OIDC subject — **functionally immutable and already present in every token**. The Plant API consumes only `uid` (→ PaperTrail whodunnit), `email` (→ all ownership), `trust_levels.plant`. Email changes are ICT-only at the IdP but do happen; nothing reconciles `owned_by`.

**Token transport:** Rails `authenticate_with_http_token` accepts `Token` and `Bearer` schemes (actionpack `TOKEN_REGEX = /^(Token|Bearer)\s+/`). Mobile mutations/sync use `Authorization: Bearer` (authenticated). Mobile's plant-browse path sends a nonstandard `Authentication:` header → **anonymous in production today** (its `plants(visibility: PRIVATE)` my-plants read returns empty; sync-down uses the correct header). Preserve, don't "fix".

**GraphQL surface (ownership-related):** `createdBy`/`ownedBy` String fields + `visibility` on all six owned types; `Visibility` enum `PRIVATE/PUBLIC/DRAFT/DELETED` + filter-only `VISIBLE` (= public+private, the resolver default); `owned_by` String filter on the five collection resolvers, composed **inside** the Pundit scope (cannot leak); no `currentUser` query; **no capability fields**. Model enum integers are frozen contract: `{ private: 0, public: 1, draft: 2, deleted: 3 }`.

**Mobile app hard contract** (verbatim documents inventoried in the audit; `app/store/Plants/action.js`, `app/store/SeedTrialReports/action.js`):
- Reads: `plants(anyName:)`, `plants(language:)` full download, `category(id).plants(first/after)`, `plant(id)` detail, `categories(first/after)`, `specimens(first/after)`, and sync-downs `plants|varieties|locations|specimens(visibility: PRIVATE)` selecting `ownedBy/createdBy/visibility/updatedAt` and (specimens) inline fragments on 7 event subtypes incl. field aliases and `deleted`.
- Writes: `createPlant/updatePlant/createVariety/updateVariety/createLocation/updateLocation/createSpecimen/updateSpecimen/evaluateSpecimen`, `softDeletePlant/Variety/Location`, hard `deleteLocation/deleteImage/deleteLifeCycleEvent`, `createImage`, and add/update mutations for all 22 life-cycle event types. **`updateSpecimen` with `visibility: DELETED` is the app's specimen-delete path.**
- Error contract: `errors { code field message value }` accessed as `errors[0].code === 400`.
- Parsing: no schema validation; unknown fields/enum values are ignored (stored as-is into SQLite); crashes only if an expected field goes null/absent (e.g. `pageInfo`, `nodes`). `__typename` dispatch on exact event type names; unknown types fall through silently.
- No ownership/trust gating client-side at all — edit/delete UI is store-membership-based; the server is the enforcer.
- Anonymous browsing of categories/plants must keep working.

**Admin SPA contract** (updatable in lockstep; full inventory in the audit): `owns()` = `isAdmin ∨ ownedBy === user.email` (`src/features/auth/usePermissions.ts`) gates all edit UI; `ownedBy` displayed via `OwnerLink` → email-keyed `/profile/$email` route; `ownedBy` filter args on 4 list/profile query groups; `VISIBILITY_OPTIONS` hardcoded in ~12 files; restore hardcodes `visibility: 'PRIVATE'`; `isDeleted = visibility === 'DELETED'` branches; codegen needs the local API running; e2e asserts on the literal string `private` and `sandbox@sandbox.com`.

## 4. Data-model inventory

- Six owned tables (`plants`, `varieties`, `specimens`, `locations`, `categories`, `images`): `created_by varchar NOT NULL`, `owned_by varchar NOT NULL`, `visibility integer DEFAULT 0 NOT NULL`. **No indexes on `owned_by` or `visibility`** — today's policy-scope queries run unindexed; new org-scoped queries must add indexes.
- UUID PKs everywhere (`pgcrypto`). `db/schema.rb` is stale; `db/structure.sql` is authoritative.
- No organizations/memberships/principals/data-source/sync columns exist anywhere. `life_cycle_events.source` is free text (seed provenance), not sync metadata.
- Children without ownership: `common_names` (governed via plant), `life_cycle_events` (delegate to specimen; own `deleted` boolean), join tables, lookups.
- PaperTrail: `versions` table standard shape, `whodunnit` = **JWT uid string** (already stable-identity), `item_id` uuid (repaired 2026-07-10), YAML-safe serializer, no metadata columns.
- Production data: 322 public plants owned by `echo@echonet.org`; sandbox writes owned by `sandbox@sandbox.com`; factories generate `created_by` ≠ `owned_by` (unlike production, where they are always equal).

## 5. Compatibility hazards

1. **Mobile is frozen.** Everything in its contract above must behave identically for the whole rollout: the `Visibility` enum (values, integer backing, input+output), `visibility: PRIVATE` meaning "my private records", `updateSpecimen visibility: DELETED` performing deletion, `ownedBy/createdBy` staying non-null-crashing email strings, soft-delete mutations and error payloads, all 22 event mutations, anonymous public read.
2. **Visibility semantics must become a facade.** If persistence moves to `publication_state + access_level + deleted_at`, legacy `visibility` (field, filter arg, mutation input) must be computed/translated bidirectionally, and the stored integer enum must never be reordered/repurposed.
3. **Private → organization visibility widening.** Mapping today's `private` to `access_level: organization` is behavior-preserving **only if** each legacy owner maps to a single-member (personal) organization. Pooling existing users into shared organizations silently exposes previously-private records to co-members — a product decision, not an engineering one.
4. **Creation without an org context.** Mobile sends no organization argument and never will. Every JWT with `plant ≥ 2` (the IdP registration default — i.e. every user) must keep creating records; the server must infer a default acting organization per principal.
5. **Trust-9 admins currently edit everything.** Removing cross-org CRUD from trust 2–9 abruptly would break real workflows; needs a compatibility window and an explicit re-mapping of current 9/10 holders to org roles.
6. **Restore contract.** SPA restore = `Update* visibility: PRIVATE`; must keep working while new soft-delete preserves prior state via `deleted_at`.
7. **Email → uid mapping lives only in the IdP.** The plant DB cannot resolve principals alone; backfill needs an IdP export, and unmatched emails (departed users, typos, `echo@`/`sandbox@`) must become explicit legacy/service principals, never fabricated uids.
8. **Performance.** New membership-joined policy scopes on unindexed columns risk regressions; the plants resolver already carries N+1-sensitive eager-loading (`plants_resolver.rb` scope comment) — scope changes must preserve it, including the loaded-association mirror in `PlantType#policy_scope_loaded`.
9. **SPA deploy topology.** SPA deploys instantly on push with no gate; API prod deploy is gated. Sequencing: API additive first, SPA after codegen against the deployed schema.
10. **CLAUDE.md staleness.** Repo docs still describe Rails 6/Ruby 2.7; actual is 8.1.3/3.4.10 (`docs/MODERNIZATION-2026-07.md`). Update alongside this work to prevent bad assumptions.

## 6. Test & observability gaps

- ~1,314 passing specs, but **all bypass HTTP auth** (schema-level `context: { current_user: }`); only `spec/requests/sandbox_mode_spec.rb` exercises the request layer, and no test signs a real JWT.
- No policy specs for Variety/Specimen/Location/LifeCycleEvent (rely on inheritance); no contract tests representing the mobile client's actual documents; no tenant-leakage or N+1 tests for scopes.
- No authorization-denial metrics/logging, no deprecated-field usage observability, no backfill audit tooling (none needed yet — nothing to backfill until now).

## 7. Facts / assumptions / unresolved questions

**Facts** are §§1–6 (verified against working trees this run; mobile inventory from the read-only audit of its source).
**Assumptions:** production DB content matches staging's 2026-07-10 prod dump; the mobile snapshot in this workspace matches the shipped app (it is labeled OLD — treat its contract as a floor, not a ceiling); IdP `uid` is never rewritten in production ops.
**Unresolved (for the user):** initial org mapping (personal vs curated), uid↔email export mechanics, role mapping for existing trust holders, sync scope, membership-admin host — see the checkpoint questions.

## 8. Initial recommendation

Follow the directional reference design with these adjustments:

1. **No IdP changes for v1.** The token already carries an immutable `uid` and the super-admin signal (`trust_levels.plant ≥ 10`). Organizations/memberships live in the Plant API DB (the IdP has no org model — only self-reported profile strings). Principals key on `(identity_issuer, external_uid)` with issuer `https://www.echocommunity.org`.
2. **Keep the legacy `visibility` contract as a computed facade** over `publication_state/access_level/deleted_at`, translating both reads and writes (including `visibility: PRIVATE` filters and `visibility: DELETED` deletes) for the supported-client window. Never touch the stored integer enum.
3. **Default to personal (single-member) organizations** for existing owners + an ECHO organization for `echo@echonet.org`/seeded content, preserving exact current semantics; shared orgs are then an administrative action, not a migration side effect. (Pending user confirmation.)
4. **Default acting organization per principal** so org-unaware clients (mobile) keep creating records server-side; multi-org users choose explicitly only in new clients.
5. **Keep Pundit; add server-computed capability fields** (`canEdit`, `canDelete`, `canRestore`, …) so the SPA's `owns()` mirror can be retired.
6. **Build the data-source/sync-conflict framework without a live integration** — no external source system exists in any repo today.
