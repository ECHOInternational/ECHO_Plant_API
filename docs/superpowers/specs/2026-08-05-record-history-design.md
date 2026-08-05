# Record History & Restore — Design

Date: 2026-08-05
Status: Approved (pending final spec review)
Repos affected: `ECHO_Plant_API` (branch `version-history`), `plant_data_admin_interface` (branch `version-history`)

## Goal

Expose the PaperTrail audit trail that has always been recorded but never surfaced: users who can edit a plant or variety can see who changed what and when, and restore a record to an earlier state. First release covers **plants and varieties**; the machinery is generic so other entities can follow.

## Constraints (from current system, verified 2026-08-05)

- PaperTrail 17; bare `has_paper_trail` on `ApplicationRecord`; custom safe-YAML serializer (`PaperTrailYamlSerializer`) with an explicit permitted-classes list (incl. `Range`, `ActiveRecord::Point`). Reify of production-era YAML is regression-tested.
- `versions` table: `object` + `object_changes` (text/YAML), `item_id` uuid (repaired + backfilled 2026-07), `metadata` jsonb (carries `principal_id`, `origin` since the ownership redesign).
- `whodunnit` = JWT uid; sync writes store the data source's service principal id.
- Ownership redesign (design.md §9): **PaperTrail is audit-only — never a sync baseline nor an authorization input.** The legacy `visibility` enum and `OrganizedResource` dual-write are frozen contracts.
- Mobile app contract is frozen: schema changes must be strictly additive.
- `ECHO_Plant_API` is a public repo: no real emails/uids in specs, fixtures, or docs.

## Decisions (user-approved)

1. **Scope**: plants + varieties first.
2. **Granularity**: aggregated timeline — a plant's history includes its common names, relation links (categories/tolerances/growth habits/antinutrients), and images. Child history accrues from deployment forward; the record's own history reaches back years.
3. **Rollback**: restore-to-a-version (whole record), recorded as a new version; per-field revert deferred.
4. **Permissions**: history visible to anyone who can *edit* the record (`update?` policy); same gate for restore. Never public (actor identity is sensitive).
5. **API shape**: record-centric — `recordHistory` connection field on `PlantType`/`VarietyType` (renamed from `history` to avoid "history of the species" misreading), server-computed diffs, per-type restore mutations.
6. **UI**: slide-over drawer opened from the detail-page header, available in view and edit mode when the server-computed `canEdit` is true.

## API design

### Schema (additive only)

- `Types::ChangeEntryType` (+ connection). Not node-addressable (added to `NODE_FORBIDDEN_TYPES`). Fields:
  - `id: ID!` — opaque global id wrapping the version PK (used by the restore mutation and as a React key).
  - `createdAt: ISO8601DateTime!`
  - `event: ChangeEventType!` — enum `CREATED / UPDATED / DELETED / RESTORED`. `RESTORED` is derived from `metadata.restored_from_version_id`.
  - `origin: ChangeOriginType!` — enum `API / SYNC / BACKFILL` from `metadata.origin` (default `API` for pre-metadata rows).
  - `actor: PrincipalType` (nullable) + `actorLabel: String!` — resolution order: `metadata.principal_id` → `whodunnit` as principal id (sync writes) → principal lookup by uid → fallback label. Batch-loaded for the page of entries.
  - `subjectType: ChangeSubjectType!` — enum `RECORD / COMMON_NAME / CATEGORY / TOLERANCE / GROWTH_HABIT / ANTINUTRIENT / IMAGE`.
  - `subjectLabel: String` — e.g. the common name text or category name; resolved at query time with a graceful fallback when the referenced row no longer exists.
  - `changes: [FieldChangeType!]!` — `{ field: String!, locale: String, before: String, after: String }`. Field names are the camelCase GraphQL names; translation changes are flattened per locale; values humanized server-side (ranges as literals, enums as their GraphQL names, booleans as true/false).
  - `restorable: Boolean!` — true only for RECORD-subject entries that are not the newest entry and whose post-change state can be reconstructed from the version chain.
- `recordHistory(first:, after:): ChangeEntryConnection` on `PlantType` and `VarietyType`, ordered newest-first, with `totalCount`. Resolving the field raises `Pundit::NotAuthorizedError` unless `policy.update?` — the schema-level `rescue_from` renders the standard 401/403.
- Mutations `restorePlantVersion(versionId: ID!)` and `restoreVarietyVersion(versionId: ID!)` following the standard mutation conventions (`authorized?` via Pundit `update?`, `{ plant|variety, errors: [MutationError] }` payload).

### History assembly (server)

- Query: `versions WHERE (item_type = 'Plant' AND item_id = :id) OR metadata @> '{"root_type":"Plant","root_id":":id"}'`, ordered `created_at DESC, id DESC`, paginated by the connection.
- **Migration**: GIN index on `versions.metadata` (`jsonb_path_ops`), created `algorithm: :concurrently` with `disable_ddl_transaction!`.
- **Child stamping**: a model concern (e.g. `VersionedUnderRoot`) declared on `CommonName`, the four plant join models, the three variety join models, and `Image`, which merges `{ root_type, root_id }` into the version `metadata` **without clobbering** the controller-supplied metadata (`principal_id`, `origin`). Implementation must account for PaperTrail merging `controller_info` and model `meta:` into the same `metadata` column (merge, not overwrite). For `Image`, the root is the `imageable` when it is a Plant or Variety.
- **Diff builder** (`app/services/`, alongside the existing service objects): parses `object_changes` through the safe serializer; maps DB columns to GraphQL field names; skips noise columns (`updated_at`, `created_at`, sync-internal columns, `translations` raw form); flattens the `translations` jsonb delta into per-locale field changes; renders join-model create/destroy versions as "added/removed" entries with the looked-up item name; **shows** `visibility` and ownership changes (meaningful audit events) while marking them non-restorable.

### Restore semantics

- Restoring entry V sets the record to its state **immediately after** V (via the PaperTrail reify chain: reify of the following version, or an "already current" payload error, code 400, when V is the newest).
- Only **editable content attributes** are applied — exactly the set accepted by `UpdatePlant`/`UpdateVariety` (the `*EditableArguments` concerns) plus translations. Never touched: `owned_by`, `created_by`, principal/organization columns, `visibility`, sync columns, timestamps. Consequences:
  - `OrganizedResource` dual-write invariant cannot be violated.
  - Sync machinery sees restore as an ordinary edit (PaperTrail stays audit-only).
  - Soft-deleted records must be restored through the existing visibility flow first; the mutation returns a payload error on deleted records.
- Applied with a normal validated save; validation failures return standard payload errors.
- The new version's metadata carries `restored_from_version_id`, rendered as event `RESTORED`.
- Child-row restore (e.g. resurrecting a deleted common name) is **out of scope for v1**: those entries appear in the timeline without a restore button.

## SPA design

New `features/history/` folder:

- **Entry point**: a "History" button in the plant/variety detail header (view and edit mode), rendered only when the server-computed `canEdit` is true. Opens a right-hand shadcn `Sheet` (new `components/ui/sheet.tsx`, source-owned).
- **List**: `useInfiniteQuery` over the `recordHistory` connection (query key `['plants'|'varieties', 'history', id]`), reverse-chronological with a "Load more" control. Each entry: actor display name (Principal display conventions), relative timestamp (new `lib/dates.ts` util; absolute time on hover), event badge (variant mapping like `visibilityVariant`), subject label for child entries, expandable diff table (field, before → after) using existing badge variants and the ECHO palette.
- **Restore flow**: button on restorable entries → `ConfirmDialog` ("Restores these fields to their values from <date>. Recorded as a new change.") → mutation → invalidate the entity root key (`['plants']`) and the history key → success toast. While the edit form has unsaved changes, the restore button is disabled with a "save or discard your edits first" hint.
- GQL documents live in the feature's `api.ts` per convention; `pnpm codegen` + `pnpm format` after adding them.

## Testing

- **API** (tagged `versioning: true` where versions must record): diff-builder and actor-resolution unit specs; request specs for `recordHistory` (including 401/403 for anonymous/non-editors and the aggregated child entries); restore mutation specs (happy path, already-current, deleted record, validation failure, excluded-fields invariance, sync-record behaves as ordinary edit); factories follow the ownership-stamp rule. RuboCop + full suite green.
- **SPA**: Vitest for diff rendering, date util, and hooks; one Playwright e2e (edit a plant → open drawer → see the change with actor and diff → restore → verify values and new RESTORED entry).

## Rollout

- Worktrees: `.worktrees/api-version-history` (created) and `.worktrees/spa-version-history` (at implementation start), both branched from their repo's default branch.
- Ship API first (additive, invisible to existing clients), then the SPA. The GIN index migration deploys with the API release. No Terraform changes.
- Mobile contract specs must remain untouched and green.

## Out of scope (recorded for later)

- Per-field revert from the diff view.
- Child-row restore (undelete a common name/image from the timeline).
- History for specimens, locations, life-cycle events, lookups; a cross-record admin audit query (approach 2's top-level `versions` query) if ever needed.
- Retention/pruning policy for the `versions` table.
