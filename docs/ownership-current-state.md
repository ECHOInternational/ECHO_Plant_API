# Record Ownership in the ECHO Open Plant Database — Current State

*Prepared as a read-only description of today's behavior, for the system owner planning a redesign. No proposals; only what exists now. File references use `path:line`. All paths are absolute.*

The trust-level ladder (read / write / admin / super-admin, keyed on `trust_levels.plant`) is documented separately in `/work/plant_data_upgrade/ECHO_Plant_API/docs/authorization-trust-levels.md` and is incorporated here by reference. This document describes the *ownership* layer that sits on top of that ladder.

---

## 1. The identity model

**There is no users table.** Every request is authenticated purely from a JWT, and the "user" exists only in memory for the duration of the request.

- `ApplicationController#require_token` (`/work/plant_data_upgrade/ECHO_Plant_API/app/controllers/application_controller.rb:22-45`) decodes the bearer token (`Authorization: Token ...`) with an RS256 **public** key built from `ENV['APPLICATION_JWT_SECRET']`. The API only *verifies* tokens; it never issues them (they come from echocommunity's IdP). It then does `@current_user = User.new(jwt_payload[0]['user'])`.
- The `User` class (`/work/plant_data_upgrade/ECHO_Plant_API/app/models/user.rb`) is a plain Ruby object, **not** an ActiveRecord model. `persisted?` returns `false` (line 50-52). It carries exactly three things from the token: `id` (from `uid`), `email` (from `email`), and `permissions` (from `trust_levels`) — see lines 6-12.
- **What identifies an owner is the email string.** Ownership is stored on records as the literal email (`owned_by`), and every ownership check compares `record.owned_by == user.email` (exact Ruby string equality — see §3). There is no user id, no foreign key, no membership record linking a person to their records. The identity is the email text, nothing more.

**Anonymous requests.** If `SANDBOX` is off and no token is presented, `authenticate_with_http_token` simply doesn't run its block, so `@current_user` stays `nil` (`application_controller.rb:23`). A `nil` user gets public-read only everywhere (see the policies in §3). A malformed/expired token renders a 401 (line 42-44).

**Email change at the IdP — orphaned records.** Because ownership is the email *string* copied onto each row at creation time, if a person's email changes at echocommunity (the IdP), their new token carries the new email, and `record.owned_by == user.email` no longer matches any of their old rows. Those records become effectively **orphaned**: the person can no longer edit or soft-delete them as an owner (only an admin/super-admin can, via override), and they won't see their private ones in `owned_by`-scoped views. Nothing in the codebase rewrites `owned_by` on an email change — there is no reconciliation job and no migration path (confirmed: no mutation or code assigns `owned_by` except at creation; see §2).

**The sandbox identity.** `set_sandbox_user` (`application_controller.rb:47-56`) activates when `ENV['SANDBOX'] == 'true'` and short-circuits JWT entirely. It injects a fixed in-memory user: `uid: 'sandbox'`, `email: 'sandbox@sandbox.com'`, `trust_levels: { 'plant' => SANDBOX_TRUST_LEVEL }` (default `2` = write; set `10` for super-admin). Any record created in sandbox is therefore owned by the literal string `sandbox@sandbox.com`.

---

## 2. The ownership fields

### Which models carry ownership columns

Two nullable-`NOT NULL` string columns, `created_by` and `owned_by`, plus an integer `visibility` enum, appear on exactly these tables (from `/work/plant_data_upgrade/ECHO_Plant_API/db/structure.sql`):

| Table | `owned_by` line | Model | Policy |
|---|---|---|---|
| `plants` | structure.sql:325 | `Plant` | `PlantPolicy` |
| `varieties` | structure.sql:428 | `Variety` | `VarietyPolicy` |
| `specimens` | structure.sql:367 | `Specimen` | `SpecimenPolicy` |
| `locations` | structure.sql:301 | `Location` | `LocationPolicy` |
| `categories` | structure.sql:147 | `Category` | `CategoryPolicy` |
| `images` | structure.sql:257 | `Image` | `ImagePolicy` |

(`db/schema.rb` is stale — it only lists a handful of 2020-era tables and stops at version `2020_08_14`; `structure.sql` is the authoritative schema.)

Each of these models validates presence of the ownership fields:
- `Plant`: `validates :owned_by, :created_by, :visibility, presence: true` (`app/models/plant.rb:9`)
- `Variety`: `.../variety.rb:5`
- `Specimen`: `.../specimen.rb:7`
- `Location`: `.../location.rb:5`
- `Category`: `.../category.rb:7`
- `Image`: `validates :name, :owned_by, :created_by, presence: true` (`.../image.rb:8`) — note Image does **not** validate `visibility` presence, though the column exists with default `0` (`private`).

### Owned vs lookup/global models

- **Owned** models subclass `OwnedResourcePolicy`: `Plant`, `Variety`, `Specimen`, `Location`, `Category`, `Image` (Image with overrides — §3).
- **Lookup / global** models have **no ownership columns at all** and their own flat policies where read is open to everyone and write requires super-admin: `Tolerance` (`app/policies/tolerance_policy.rb`), `GrowthHabit` (`growth_habit_policy.rb`), `Antinutrient` (`antinutrient_policy.rb`), `ImageAttribute` (`image_attribute_policy.rb`). Each: `index?`/`show?` → `true`; `create?`/`update?`/`destroy?` → `user&.super_admin?`.
- **`LifeCycleEvent`** has no ownership columns of its own; it *delegates* ownership to its `Specimen` (§3).
- **`CommonName`** (child of Plant) has no ownership columns; it is governed indirectly through `plant.update?` in the common-name mutations.
- **Join tables** (`categories_plants`, `tolerances_plants`, etc.) have no ownership; they are mutated through the owning plant/variety's `update?`.

### How ownership is SET at creation

Every create mutation stamps **both** `created_by` and `owned_by` from `context[:current_user].email` server-side. The client **cannot** supply either value — there is no `owned_by`/`created_by` argument anywhere.

- `CreatePlant`: `.merge!(created_by: context[:current_user].email).merge!(owned_by: context[:current_user].email)` (`app/graphql/mutations/create_plant.rb:45-46`)
- `CreateVariety`: `create_variety.rb:41-42`
- `CreateSpecimen`: `create_specimen.rb:54-55`
- `CreateLocation`: `create_location.rb:52-53`
- `CreateCategory`: `create_category.rb:31-32`
- `CreateImage`: `process_attributes` sets `created_by`/`owned_by` from `context[:current_user].email` (`create_image.rb:46-47`)

The creator always becomes the owner. There is no way to create a record on behalf of another user (even for an admin) — the email is always the caller's own.

### Whether ownership can be CHANGED

**No.** No mutation exposes `owned_by` or `created_by` as a writable argument. Verified by grep across `app/graphql/`: the only assignments to `owned_by`/`created_by` are the six create mutations above. The editable-argument concerns that back both create and update (`app/graphql/mutations/concerns/plant_editable_arguments.rb`, `variety_editable_arguments.rb`) declare only translatable text, boolean, enum, and range fields — **no ownership fields**. The update mutations (`update_plant.rb`, `update_variety.rb`, `update_specimen.rb`, `update_location.rb`, `update_category.rb`, `update_image.rb`) never touch `owned_by`.

**There is no transfer mechanism.** No "transfer ownership" mutation, no admin reassignment, no bulk re-owner. Once `owned_by` is written at creation it is immutable through the public API surface. (It could only change by direct database manipulation.)

---

## 3. What ownership grants

The authority is `OwnedResourcePolicy` (`/work/plant_data_upgrade/ECHO_Plant_API/app/policies/owned_resource_policy.rb`), which `PlantPolicy`, `VarietyPolicy`, `SpecimenPolicy`, `LocationPolicy`, `CategoryPolicy` inherit unchanged (each is a one-line empty subclass, e.g. `plant_policy.rb`).

### Per-action semantics (base policy)

- **`index?`** → always `true` (line 24). List access is gated by the *Scope*, not by `index?`.
- **`show?`** (lines 28-34): visible if user is admin, **or** `record.owned_by == user.email`, **or** the record's `visibility` is `public`. So: owner sees own records at any visibility; everyone (including anonymous) sees public records; admins see everything.
- **`create?`** (lines 36-38): `user&.can_write?` — any writer (trust ≥ 2). Ownership is irrelevant to create; the new record simply becomes yours.
- **`update?`** (lines 40-44): requires `can_write?` **and** (`user.admin?` **or** `record.owned_by == user.email`). So a writer may edit only records they own; an admin (trust ≥ 9) may edit anyone's.
- **`destroy?`** (lines 46-50): requires `can_write?` **and** (`user.super_admin?` **or** `record.owned_by == user.email`). The owner can destroy their own; otherwise only super-admin (trust ≥ 10). Note "destroy" here is the Pundit action name; in practice the plant/variety/specimen/location delete mutations authorize on `:update?` and soft-delete (see §5), while true hard-destroy is super-admin territory.

### The Scope (which records appear in lists)

`OwnedResourcePolicy::Scope#resolve` (lines 14-22):
- admin → `scope.all` (everything, all visibilities including `deleted`);
- authenticated non-admin → `scope.where(visibility: :public).or(scope.where(owned_by: user.email))` — public rows plus your own (any visibility);
- anonymous → `scope.where(visibility: :public)` only.

### Visibility × owner × role matrix (read)

| Record visibility | Anonymous | Writer, not owner | Writer, **owner** | Admin (≥9) |
|---|---|---|---|---|
| public | read | read | read + edit | read + edit + destroy |
| private | hidden | hidden | read + edit + destroy | read + edit + destroy |
| draft | hidden | hidden | read + edit + destroy | read + edit + destroy |
| deleted | hidden | hidden | read (via scope) + edit | read + edit |

Notes: "owner destroy" on public rows requires super-admin per `destroy?` unless the owner-branch applies — the owner branch (`record.owned_by == user.email`) grants destroy to the owner regardless of visibility. Non-owner writers get *nothing* on non-public records — such records are invisible to them, so they cannot even attempt a write. The `deleted` visibility is just another enum value; owners and admins still see and can act on soft-deleted rows (see §5).

### The delegation chain — life-cycle events

`LifeCycleEvent` owns nothing directly. In the model (`app/models/life_cycle_events/life_cycle_event.rb:24-25`) it `delegate :owned_by, to: :specimen` and `delegate :visibility, to: :specimen`. Its policy (`app/policies/life_cycle_event_policy.rb`) delegates `update?` straight to the parent specimen: `SpecimenPolicy.new(@user, @record.specimen).update?` (lines 6-8). The Scope (lines 18-26) joins through `specimens` and filters on `specimens.visibility = public OR specimens.owned_by = user.email` (admins see all). So **an event's owner is its specimen's owner**; there is no independent event ownership, and no `create?`/`destroy?` overrides (event creation/deletion flows through mutations that authorize on the specimen's `update?`).

### The polymorphic case — images

`Image` is polymorphic via `imageable` (`app/models/image.rb:16`). Image **also has its own `owned_by`/`created_by` columns** (set to the uploader's email at `CreateImage`), and `ImagePolicy` (`app/policies/image_policy.rb`) grants rights through **either** owner:
- `show?`: `return true if user && record.imageable.owned_by == user.email`, else `super` — and the `super` (`OwnedResourcePolicy#show?`) checks public visibility **or the image's own `owned_by`** or admin — lines 5-9.
- `update?` / `destroy?`: `return true if record.imageable.owned_by == user.email` (given `can_write?`), else `super` — which again checks the **image's own `owned_by`** (or admin) — lines 11-23.
- `create?` → hard-coded `false` (lines 25-28): images cannot be created directly; they are only created through `CreateImage`, whose `authorized?` calls `authorize obj, :update?` on the *imageable* (`create_image.rb:75-78`).

So an image is effectively editable by **the imageable's owner OR the image's own uploader OR an admin** — a two-owner union. In practice the two owners usually coincide (creating an image requires `update?` on the imageable, so the uploader is normally the imageable's owner), but they diverge when an admin uploads to someone else's record: the image records the admin as `owned_by` while the record's owner also has full rights over it via the imageable path. Because `imageable` may itself be a `LifeCycleEvent`, the check can chain through the event's delegated `owned_by` to the specimen.

### Models with different ownership rules than the base

- **`Image`** — overrides as above (checks imageable's owner, not its own; `create?` = false).
- **`LifeCycleEvent`** — not an `OwnedResourcePolicy` subclass at all; delegates to specimen.
- **Lookups** (`Tolerance`, `GrowthHabit`, `Antinutrient`, `ImageAttribute`) — no ownership concept; super-admin-gated writes, open reads.
- **`Upload`** (`app/policies/upload_policy.rb`) — the presigned-URL mutation; `show?`/`index?` require `can_write?`; there is no record and no ownership (it returns a presigned S3 PUT URL, no DB row).

---

## 4. Ownership in the API surface

### The `ownedBy` filter

Every collection resolver exposes an `owned_by` option that filters to a specific owner email:
- `PlantsResolver` (`app/graphql/resolvers/plants_resolver.rb:45-53`): `option :owned_by ... scope.where(owned_by: value)`.
- Same pattern in `VarietiesResolver` (`varieties_resolver.rb:30-38`), `SpecimensResolver` (`specimens_resolver.rb:30-38`), `LocationsResolver` (`locations_resolver.rb:30-38`), `CategoriesResolver` (`categories_resolver.rb:30-38`).

Crucially, this filter is **composed on top of the Pundit policy scope** — every resolver sets `scope { Pundit.policy_scope(current_user, Model).i18n ... }` (e.g. `plants_resolver.rb:20`), and `apply_owned_by_filter` narrows *within* that already-authorized scope. So passing someone else's email as `ownedBy` can only ever return their **public** records (plus your own if you happen to match) — it cannot leak private/draft records. It is a convenience filter, not an access-control bypass.

### `ownedBy` / `createdBy` exposure in types

Both are exposed as read-only String fields on each owned type:
- `PlantType` (`app/graphql/types/plant_type.rb:92,95`), `VarietyType` (`variety_type.rb:75,78`), `SpecimenType` (`specimen_type.rb:17,20`), `LocationType` (`location_type.rb:18,21`), `CategoryType` (`category_type.rb:20,23`), `ImageType` (`image_type.rb:30,33`).

Production confirms these render as the literal email — a live query returned `ownedBy: "echo@echonet.org"`, `createdBy: "echo@echonet.org"` for public plants.

### The SPA's use of ownership

*(from the admin interface at `/work/plant_data_upgrade/plant_data_admin_interface`)*

- **Identity comes from the same JWT.** The SPA decodes the token client-side: `decodeClaims()` (`src/lib/auth/claims.ts:9-23`) base64-decodes the JWT payload and pulls `user.uid`, `user.email`, and `user.trust_levels.plant`. The token lives in `sessionStorage['plant-admin.token']` (`src/lib/auth/session.ts:8`). The display *name* is not in the token; it's fetched separately from the IdP userinfo endpoint after login (`src/routes/auth.callback.tsx:59`). So the SPA's notion of "who am I" is the same email string the API uses.

- **The `owns()` helper.** `usePermissions()` (`src/features/auth/usePermissions.ts`) computes `isAdmin = trust > 8` (line 24) — matching the API's `admin?` threshold exactly — and exposes `owns: (ownedBy) => isAdmin || (!!user && !!ownedBy && ownedBy === user.email)` (line 30). This is a faithful client-side mirror of the server rule: admin overrides, otherwise exact email match. `canWrite` (`trust > 1`, line 27) is separate and governs *create*, while `owns()` governs *edit/delete* of a specific record. Sandbox mode injects `sandbox@sandbox.com` at trust 10 (line 6).

- **`canEdit` gating is ownership-based (with admin override), UI-only.** Every detail page derives `const canEdit = owns(record.ownedBy)` and hides Edit/Delete/Danger-zone controls when false: plants (`src/features/plants/PlantDetailPage.tsx:40`), varieties (`src/features/varieties/VarietyDetailPage.tsx:294`), specimens (`src/features/specimens/SpecimenDetailPage.tsx:40`, which also passes `canEdit` into `TimelineTab` to gate event add/delete), locations (`src/features/locations/LocationDetailPage.tsx:36`), categories (edit/delete gated per-row via `owns(row.ownedBy)`, `src/features/categories/CategoriesPage.tsx:131`). This is purely cosmetic gating; the API enforces regardless (§3).

- **Owner filters and a profile page exist.** Plants, specimens, and locations list pages each have an "Owned by me" checkbox (filters `ownedBy` to `user.email`) plus a free-text "Owner email" input, both feeding the resolver's `ownedBy` argument (e.g. `src/features/specimens/SpecimensPage.tsx:45-63,192-208`; `src/features/plants/PlantsPage.tsx:62,225-244`; `src/features/locations/LocationsPage.tsx:86,225-268`). Categories has no owner filter. A **profile page** at `/profile/$email` (`src/features/profile/ProfilePage.tsx`, data via `src/features/profile/profile-api.ts` using the `ownedBy` argument) lists all records owned by a given email; owner emails throughout the UI are rendered as `OwnerLink` (`src/components/OwnerLink.tsx`) linking to that profile (showing the current user's display name when it's you, the raw email otherwise, an em-dash when null).

- **`ownedBy` is displayed; `createdBy` is fetched but never shown.** `ownedBy` appears as an owner column in every list and an "Owner:" line in every detail header (e.g. `PlantDetailPage.tsx:60`, `SpecimenDetailPage.tsx:89`, `LocationsPage.tsx:201`). `createdBy` is selected in several detail/list GraphQL queries but is not rendered anywhere in the UI — consistent with the fact that `created_by` and `owned_by` are always identical today.

---

## 5. Edge behaviors worth knowing before a redesign

- **Soft-delete does not touch ownership.** `SoftDeletePlant` (`app/graphql/mutations/soft_delete_plant.rb:50-56`) simply does `plant.update(visibility: :deleted)`; `owned_by`/`created_by` are unchanged. Restore is done by `UpdatePlant`/`UpdateVariety` setting `visibility: PRIVATE` — again ownership is untouched. So a soft-deleted record retains its owner, and the owner still sees it via the policy scope (their own rows at any visibility). The same soft-delete authorizes on `:update?` (line 17-19), i.e. owner-or-admin, and enforces a dependency check (active child specimens/varieties) unless `force: true`.

- **Versions / paper_trail is who-did-what, not who-owns.** `ApplicationRecord` calls `has_paper_trail`, and `set_paper_trail_whodunnit` runs on every request (`application_controller.rb:9`). `whodunnit` on the `versions` table records the acting user for each change — but it is entirely separate from `owned_by`. `whodunnit` is derived from `current_user` (the actor of a given change); `owned_by` is the immutable creator stamped once. A record edited by an admin will have that admin in the latest `whodunnit` while `owned_by` still names the original creator. (The `versions` table stores `whodunnit` as a plain string — same identity fragility as `owned_by`.)

- **Seeded / legacy data ownership.** All seeded records are owned by the literal string **`echo@echonet.org`**: categories (`db/seeds.rb:17-18`), plants (`seeds.rb:103-104`), varieties (`seeds.rb:177-178, 194-195`), and more (`seeds.rb:218-219`), all `visibility: :public`. Production confirms real public plants carry `owned_by: "echo@echonet.org"`. This means the bulk of production content is owned by a single shared "echo" identity that no individual logs in as — those records are effectively editable only by admins (trust ≥ 9), since no ordinary user's email matches `echo@echonet.org`. (The task mentions `larrytest@echonet.org` as a known test-row owner; no such literal appears in `db/seeds.rb`. A live production probe returns `totalCount: 0` for `plants(ownedBy: "larrytest@echonet.org")` while `echo@echonet.org` owns 322 public plants — so any `larrytest` rows are not public/seeded content; they would be private records created interactively by a test account, invisible to an anonymous probe. Worth checking the live DB directly with admin access if it matters.)

- **Email matching is case-sensitive and exact.** Every ownership check is a plain Ruby `==` string comparison: `record.owned_by == user.email` in `owned_resource_policy.rb:31,43,49`, in `image_policy.rb`, and the in-Ruby mirror `r.owned_by == user.email` in `plant_type.rb:232`. There is no `downcase`, no normalization, no trimming. `Alice@echo.org` and `alice@echo.org` are different owners. The `where(owned_by: value)` SQL filters are likewise exact (Postgres `=`, case-sensitive for `varchar`).

- **Ownership is enforced in two places, both consistent with Pundit.** Almost all enforcement is Pundit (policies invoked via `authorize` in mutation `authorized?` methods and via `Pundit.policy_scope` in resolvers). The one non-Pundit spot is `PlantType#policy_scope_loaded` (`plant_type.rb:227-236`), an **in-Ruby re-implementation** of `OwnedResourcePolicy::Scope#resolve` used to filter the already-loaded `varieties` association without a second SQL query. It faithfully mirrors the policy (admin → all; user → public-or-owned; anonymous → public). No mutation performs its own ad-hoc ownership check outside the policy — all create/update/delete mutations call `authorize` (verified in `create_variety.rb:30`, `create_specimen.rb:23`, `relations/update_relations_base_mutation.rb:27`, etc.).

- **Child ownership is independent of parent ownership.** `CreateVariety` authorizes on the `Variety` *class* (`create_variety.rb:29-30` → `Variety, :create?` → just `can_write?`), **not** on the parent plant. The new variety's `owned_by` is the creator's email, regardless of who owns the parent plant. The same holds for `CreateSpecimen`. Consequently a plant owned by user A can accumulate varieties/specimens owned by users B, C, D — a single logical "plant" tree can have many different owners across its nodes, and editing rights fragment accordingly. Life-cycle events are the exception (they delegate to the specimen, so they can't diverge from their specimen's owner).

---

## 6. Properties of the current design

A neutral list of consequences a redesign should weigh (no recommendations implied):

1. **Single-owner only.** Each record has exactly one `owned_by` email. There is no concept of co-owners, multiple stewards, or shared editing below the admin tier.
2. **No groups, teams, or organizations.** Ownership cannot be assigned to an org, project, or role — only to one individual's email. Everyone at ECHO who needs to edit shared content must either be an admin or share a login/email.
3. **Email-as-identity is fragile.** Identity is a plain email string copied onto each row, with no user id or foreign key. An email change at the IdP orphans all prior records for that person (no reconciliation exists). Typos or case differences at creation silently create a distinct "owner."
4. **No ownership transfer or reassignment.** Once stamped at creation, `owned_by` is immutable through the API (no mutation exposes it; no admin transfer tool). Handing a record to a new steward, or cleaning up after a departed contributor, requires direct DB access.
5. **Creator is always the owner; no "on behalf of."** Even admins/super-admins cannot create a record owned by someone else — the email is always the caller's own.
6. **`created_by` and `owned_by` are always identical today.** They are set to the same value at creation and neither ever changes, so the two-column distinction carries no information in current behavior. (`whodunnit` in paper_trail is the only place a *different* actor is recorded, and it is unrelated to ownership.)
7. **Admin override is broad and role-based, not scoped.** An admin (trust ≥ 9) can read/edit *every* record of every owner; a super-admin (≥ 10) can also hard-destroy and manage lookups. There is no notion of "admin over a subset" — override is global once the trust threshold is crossed.
8. **Bulk/legacy content sits under one shared identity (`echo@echonet.org`).** Most production data is owned by an address no individual authenticates as, so in practice only admins can edit it — ordinary contributors cannot take ownership of or edit legacy public content.
9. **Ownership fragments across the domain tree.** Varieties and specimens are owned by whoever created them, independent of the parent plant's owner, so one logical plant can span many owners with correspondingly fragmented edit rights. Life-cycle events are the sole exception (owner delegated to specimen).
10. **Images have a split identity.** An image records its uploader in its own `owned_by`, but authorization ignores that and uses the *imageable's* owner. The stored image-owner and the effective-owner can differ.
11. **Case-sensitive, unnormalized matching.** All ownership comparisons are exact string equality; there is no canonicalization, so ownership correctness depends entirely on the IdP always emitting a byte-identical email.
12. **Ownership is entangled with visibility.** "Can I see it" and "can I edit it" both mix `visibility` and `owned_by`; there is no separate sharing/ACL layer — visibility is the only lever besides ownership and the admin role.
