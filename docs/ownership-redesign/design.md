# Ownership Redesign — Design & Decision Record

*Status: accepted 2026-07-13 (user-confirmed choices marked ✓). Companion: `discovery.md` (verified current state), `rollout.md` (deployment/rollback runbook, written alongside implementation).*

## 0. Decisions settled with the product owner

| # | Decision | Choice |
|---|---|---|
| D1 ✓ | Legacy owner mapping | Personal (single-member) organization per existing owner email; `echo@echonet.org` content → the **ECHO organization**. Personal orgs are a compatibility shim, expected to be revisited. |
| D2 ✓ | Email→uid mapping | Export task at the IdP produces `{uid, email, name}`; mapping is 1:1 and expected complete. Unmatched emails become legacy principals (no fabricated uids), itemized in reports. |
| D3 ✓ | Trust transition | `plant ≥ 10` = system superuser (JWT, permanent). Trust-9 global admin behavior **retained through rollout**, removed in the cleanup phase once ECHO-org memberships cover staff. Trust 2–8 users act through their personal org. |
| D4 ✓ | Sync scope | Full data-source/sync-conflict framework with tests; **no live integration** (no source system exists). |
| D5 ✓ | Membership authority | **IdP-authoritative** organizations & memberships (they will later govern resources too), administered in new controlled tables/UI — never the self-reported `users.organization_name` profile fields. |
| D6 ✓ | Membership delivery | **JWT claims**, same channel as `trust_levels`. Revocation latency = token lifetime (≤2h) + refresh, identical to trust-level changes today. |
| D7 ✓ | Personal orgs | **Plant-API-local shim** (`kind: personal`), invisible to the IdP directory and other services. IdP holds only real organizations. |
| D8 ✓ | Role shape | **Per-domain roles** on a membership (`roles: {"plant": "editor"}`), mirroring the `trust_levels` per-domain precedent. |

## 1. Identity & principal lifecycle (Plant API)

New table `principals`:

```text
id uuid PK
identity_issuer varchar           -- 'https://www.echocommunity.org' (from token iss)
external_uid varchar              -- IdP users.uid; NULL for legacy/service principals
email varchar                     -- mutable profile data, display + legacy matching only
display_name varchar
kind varchar                      -- 'human' | 'service'
last_authenticated_at timestamptz
UNIQUE (identity_issuer, external_uid) WHERE external_uid IS NOT NULL
```

On each authenticated request (after JWT verification, unchanged): resolve-or-create the principal by `(iss, user.uid)`; refresh `email`/`last_authenticated_at` only when changed/stale (cheap read path). The Pundit "user" becomes a request-scoped **actor** combining: the persistent principal, the raw trust ladder (unchanged semantics), and the token's organization membership claims. Anonymous requests keep a nil actor. Sandbox mode synthesizes a sandbox principal the same way.

`created_by`/`owned_by` email strings remain written for the legacy contract; `created_by_principal_id` becomes the durable creator identity ("update records they created" checks the principal, never email). Email changes at the IdP no longer orphan anything once org authorization is authoritative.

Service principals (`kind: 'service'`, no uid) represent importers/migrations; the backfill itself runs as `migration@plant-api` service principal for PaperTrail attribution.

## 2. Organizations & memberships

**IdP (`ECHOcommunity`), new controlled tables:**

```text
organizations: id uuid PK, name, slug UNIQUE, created/updated_at
organization_memberships: id, organization_id FK, user_id FK,
  roles jsonb                      -- {"plant": "editor"} ; domain-keyed
  revoked_at timestamptz NULL      -- active = revoked_at IS NULL
  UNIQUE (organization_id, user_id)
```

Administered under the existing `/admin` namespace, gated exactly like trust levels (`general_trust_level > 8`). Seed: the **ECHO** organization; staff memberships assigned by admins.

**JWT claim (additive, doorkeeper.rb):**

```json
"user": { ...existing..., "organizations": [
  { "id": "<org uuid>", "name": "ECHO", "roles": { "plant": "editor" } }
] }
```

Only active memberships; key omitted when empty. Old consumers (mobile, current API) ignore it. Trust levels stay in the token unchanged.

**Plant API, local mirror + shim:**

```text
organizations: id uuid PK, name,
  kind varchar                     -- 'real' | 'personal'
  external_idp_id uuid UNIQUE NULL -- IdP org id (real orgs)
  principal_id uuid UNIQUE NULL    -- owning principal (personal orgs)
  CHECK (kind='real' AND external_idp_id IS NOT NULL AND principal_id IS NULL
      OR kind='personal' AND principal_id IS NOT NULL AND external_idp_id IS NULL)
```

Real-org rows are upserted from claims on request (id + name refresh) and by the backfill; there is **no local membership table** — real-org membership/roles come from the claim at request time; a personal org's sole implicit member is its principal, with implicit role `org_admin`.

## 3. Roles & capabilities

Roles (strings, no numeric ladder): `member`, `contributor`, `editor`, `steward`, `org_admin`; plus the JWT system-superuser (`trust_levels.plant ≥ 10`). Centralized in one capability module (`OrganizationRole`), consumed by every policy — capability names, not role comparisons:

| Capability | member | contributor | editor | steward | org_admin | superuser |
|---|---|---|---|---|---|---|
| read org records | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (all orgs) |
| create for org | | ✓ | ✓ | ✓ | ✓ | ✓ |
| update own-created | | ✓ | ✓ | ✓ | ✓ | ✓ |
| update any org record | | | ✓ | ✓ | ✓ | ✓ |
| resolve ordinary sync conflicts | | | ✓ | ✓ | ✓ | ✓ |
| soft-delete / restore | | | | ✓ | ✓ | ✓ |
| accept upstream deletion | | | | ✓ | ✓ | ✓ |
| manage memberships & data sources | | | | | ✓ (IdP UI) | ✓ |
| ownership transfer, source correction, hard delete | | | | | | ✓ |

"Update own-created" = `created_by_principal_id == actor.principal.id` within the owning org. Personal-org owner = `org_admin` of that org (exactly today's rights over own records). Source-org membership grants nothing when source ≠ owner.

## 4. Ownership, source & sync columns (independently owned models)

Applied to `plants`, `varieties`, `specimens`, `locations`, `categories` (NOT images — see §6):

```text
owner_organization_id uuid FK NULL→(backfilled)→NOT NULL later
source_organization_id uuid FK
created_by_principal_id uuid FK
data_source_id uuid FK NULL, source_record_id varchar NULL,
source_updated_at, last_synced_at, source_digest varchar, sync_state varchar
publication_state varchar        -- 'draft' | 'published'
access_level varchar             -- 'organization' | 'public'
deleted_at timestamptz NULL, deleted_by_principal_id uuid FK NULL
UNIQUE (data_source_id, source_record_id) WHERE data_source_id IS NOT NULL
INDEX owner_organization_id; partial INDEX deleted_at; INDEX (visibility), (owned_by)  -- legacy scopes, currently unindexed
```

Server-assigned only (no client mass-assignment path). Native records: `source_organization_id = owner_organization_id`, no data source. Ownership transfer = superuser mutation changing owner org only (source attribution untouched). A shared `OrganizedResource` concern declares enums/validations/scopes; columns stay physical per table (security-critical filters, real FKs).

`data_sources` (org-owned, credentials NOT in DB — env/SM only) and `sync_conflicts` (syncable ref, conflict_type, base/local/incoming payloads, status, resolution, resolved_by_principal_id, sync-run metadata) per the reference design. Three-way comparison over **source-managed attributes only** — authorization/workflow/deletion state is never feed-writable. Tombstones are never auto-resurrected; upstream deletion creates a reviewable conflict; acceptance of upstream deletion requires steward+.

## 5. Visibility, publication, deletion — the facade

New persistence: `publication_state` × `access_level` × `deleted_at`. Legacy `visibility` **column** stays and stays synced (never reordered: `{private:0, public:1, draft:2, deleted:3}`).

Bidirectional mapping (single module, used by dual-write, facade reads, and backfill):

| legacy visibility | publication_state | access_level | deleted_at |
|---|---|---|---|
| `private` | published | organization | NULL |
| `public` | published | public | NULL |
| `draft` | draft | organization | NULL |
| `deleted` | (preserved prior) | (preserved prior) | set |

Reads: effective status = `deleted` when `deleted_at`, else publication state; legacy `visibility` field/filters compute through the mapping (identical by construction while dual-write holds; invariant-checked). Writes: legacy `visibility:` args translate through the same mapping — `DELETED` sets `deleted_at` (preserving prior state — strictly better restore than today), restore-by-`visibility: PRIVATE` clears `deleted_at` and sets published+organization (today's exact outcome). New API surface: `publicationState`/`accessLevel` args + explicit `restore*` mutations. Drafts are never publicly exposed; anonymous read = published + public + not deleted, same rows as today's `public`.

`DeleteLifeCycleEvent`'s separate `deleted` boolean on events is untouched (inherited child, delegates to specimen).

## 6. Ownership boundaries & relationships

- Independent owner+source orgs: Plant, Variety, Specimen, Location, Category.
- Inherited (no independent ownership in the new model): LifeCycleEvent→specimen, CommonName→plant, Image→imageable (the legacy image two-owner union survives only inside the legacy compatibility rules; new-model rights flow solely through the imageable chain, including nested event→specimen). Media attribution fields stay metadata, not authorization.
- Cross-org references: creating a variety/specimen under another org's parent requires **read access to the parent, enforced at create time** — `CreateVariety`/`CreateSpecimen` authorize `:show?` on the referenced plant/variety (a caller cannot reference, or probe the existence of, a parent they cannot see). Grants no edit rights either direction. Parent soft-deletion neither cascades to nor is vetoed by cross-org children.
  - **As-built deviation:** the reference design also called for parent-field *resolvers* (`variety.plant`, `specimen.plant`, `specimen.variety`) to null out a hidden parent. This was implemented and then reverted: `specimen.plant` is a `null: false` field the frozen mobile client reads on every seed-trial sync, and gating it breaks that sync when a referenced catalog plant is later unpublished. The compensating control is the create-time `:show?` check above, which prevents the attacker-constructed case. The residual — a *public* child whose parent is unpublished *after* the reference is created leaking that parent's directly-attached scalars — is deferred to S7 cleanup (a reconciliation that unpublishes orphaned public children, viable once the mobile client tolerates nullable parents). Tracked as a known limitation, not silently dropped.
- Join-table mutations authorize through the parent record being modified (already true; preserved).
- Lookups (Tolerance/GrowthHabit/Antinutrient/ImageAttribute) unchanged: public read, superuser write.

## 7. Pundit behavior & the transition

Policies stay Pundit; scopes stay the sole list gate. During rollout, effective authorization = **legacy rules ∨ new org rules** (strict widening only where memberships exist — with personal orgs this is a no-op except ECHO staff gaining membership rights over ECHO content, which is intended):

- `show?`: public(published+public) ∨ actor reads via owning-org membership ∨ legacy owner-email ∨ legacy admin(9) ∨ superuser.
- `create?`: membership with create capability in the acting org (personal org always qualifies) ∨ legacy `can_write?` (which now resolves to the personal org — same thing).
- `update?/destroy?`: capability in owning org (incl. own-created rule) ∨ legacy owner-email ∨ legacy admin/superadmin overrides (D3 window).
- Scope: `deleted_at`-aware union of public rows, rows of orgs the actor can read, legacy `owned_by` rows, all rows for legacy-admin/superuser. Tested for tenant leakage and N+1 (the eager-loading contract in `plants_resolver.rb` and the loaded-association mirror `PlantType#policy_scope_loaded` are updated in lockstep).

Cutover (flag): `ORG_AUTHZ_CUTOVER=log_only` makes `OwnedResourcePolicy#log_legacy_divergence` emit an `authz.legacy_divergence` event whenever access is granted only by a legacy branch and would be denied post-cleanup (enforcement is unchanged in this stage) → the legacy branches are removed in S7 cleanup once a soak window shows zero such events. Server-computed capability fields (`canEdit`, `canDelete`, `canRestore`, on all six types) are contract-tested to agree with Pundit, so clients stop reproducing policy.

**Relay node authorization:** `node(id:)`/`nodes(ids:)` are custom resolvers (not the graphql-ruby default, which did a raw `find` and bypassed the policy scope). They resolve policy-governed types through `Pundit.policy_scope` — a missing or invisible record is an indistinguishable coded 404 — and forbid identity/provenance types (`Principal`, `Organization`, `DataSource`, `SyncConflict`) from being node-addressable so global IDs cannot enumerate emails or org names. The legacy `visibility: PRIVATE` collection filter is scoped to the caller's own records for non-admins, preserving its pre-redesign "my private records" meaning for the frozen mobile client; org-visible records surface under the default `VISIBLE` scope for org-aware clients.

**Acting organization:** optional `organizationId` argument on create mutations; default = the actor's personal org (org-unaware mobile keeps working unchanged); validated against create capability. The server assigns all protected fields.

## 8. API contract evolution

Additive only in rollout: new fields (`ownerOrganization`, `sourceOrganization`, `createdByPrincipal`, `publicationState`, `accessLevel`, `deletedAt`, capabilities), new types (`OrganizationType`, `PrincipalType`, `DataSourceType`, `SyncConflictType`), new args, new mutations (restore, transfer, conflict resolution). Nothing renamed/removed/retyped; `ownedBy/createdBy` keep returning the stored email strings; `visibility` field/args/enum behave identically via the facade; mutation error payload shape unchanged. Mobile's inventoried documents are locked in by contract specs (`spec/contracts/`). Deprecations are annotations + usage logging only until the cleanup phase.

## 9. PaperTrail

`whodunnit` already carries the stable JWT uid — kept. Add `versions.metadata jsonb` populated via `info_for_paper_trail`: acting principal id, acting org id, change origin (`api|backfill|sync`), data-source/sync-run/conflict ids when applicable. Historical email-string versions remain readable (no rewrite). PaperTrail is audit only — never the sync baseline (that's `source_digest`/snapshot) nor an authorization input.

## 10. Backfill & migration plan

All schema changes additive + nullable first; batched backfills outside schema migrations; concurrent indexes; `NOT NULL`/FK validation as separate later steps (PG on RDS, tables are small — thousands of rows — but the discipline stands).

`rake ownership:backfill` (idempotent, resumable, `DRY_RUN=1` default-on, per-model batches):
1. Load IdP export `{uid, email, name}` (D2) + config: ECHO org IdP uuid, shared-email list (`echo@echonet.org`, `sandbox@sandbox.com`).
2. Upsert principals for every distinct `owned_by`/`created_by`/`whodunnit`-relevant email via the mapping; unmatched → legacy principal (email kept, no uid); shared emails → service principals.
3. Create the local ECHO org (real, linked) and personal orgs for each human principal.
4. Per record: `created_by_principal_id` from `created_by`; owner/source org from `owned_by` (ECHO for shared emails); publication/access/deleted from `visibility` (§5; `deleted_at` approximated from `updated_at`, documented).
5. Report (before/after counts): records touched/skipped, unmapped emails, principals/orgs created, rows failing invariants, duplicates. Never fabricates identities; never flips a record's effective visibility.

Rehearsed on staging (prod dump). Verified by an invariant task (`rake ownership:verify`): no owned record without owner org/source org/creator principal, facade↔column agreement, no cross-org leakage probes.

## 11. Deployment sequence & rollback (summary — full runbook in rollout.md)

| Stage | Change | Rollback |
|---|---|---|
| S1 | IdP: org tables + admin UI + additive JWT claim + export task | revert deploy; claim additive, nothing consumes it |
| S2 | API: additive schema + principal/org resolution (shadow — authz unchanged) | revert deploy; new tables inert |
| S3 | Backfill (staging rehearsal → prod dry-run → prod) | data additive/idempotent; authz still legacy |
| S4 | API: dual-write, facade parity checks, org-union authz + capability fields (flagged) | flag off → exact legacy behavior |
| S5 | SPA: capabilities, org display, acting-org picker | SPA re-deploy previous build |
| S6 | Cutover flag: new model authoritative; legacy branches log-only | flag revert (dual-write kept both representations true) |
| S7 (cleanup, later) | remove trust-9 override; deprecate legacy fields; NOT NULL enforcement | separate change, own evidence gates |

Observability added in S2–S6: authz denial logging (policy, action, actor, decision source legacy/new), legacy-arg usage counters, backfill/invariant reports, sync-conflict counts. No tokens/secrets logged.

## 12. Deviations from the directional reference design

1. **Membership authority at the IdP via JWT claims** (D5/D6) instead of app-DB memberships — chosen for multi-service reuse (resources next). Consequences addressed: staleness/revocation = token lifetime (accepted, matches trust-level precedent); multi-app consistency = one directory; admin ownership = existing IdP super-admin workflow; rollback = claim is additive. The API keeps only an org identity mirror, not membership rows.
2. **Personal orgs as a plant-local shim** (D7) rather than first-class orgs — keeps the IdP directory clean and today's semantics exact; flagged for post-v1 revisiting.
3. **Legacy visibility column stays synced** through cutover (not just an API-layer facade) so rollback at any stage needs no data surgery.
4. Soft-delete via `deleted_at` *improves* restore (prior state preserved) while the legacy restore path (`visibility: PRIVATE`) still lands on today's exact outcome.
