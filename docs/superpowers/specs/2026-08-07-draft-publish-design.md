# Draft and publish: staged edits to published records

**Date:** 2026-08-07
**Status:** Design approved, not yet planned
**Scope:** ECHO_Plant_API + plant_data_admin_interface

## Problem

Today `visibility: draft` means "hidden". A record is either visible or it is
not, and there is exactly one copy of it. So an editor who starts a Swahili
translation and cannot finish it has only one lever: mark the whole record
draft. The record vanishes from public view, taking its finished English and
Spanish content with it, because every locale lives in one Mobility container
blob on one row.

The same shape of problem applies to any partial edit of a published record.
There is no way to work on a change while the current version stays alive.

Families make it worse in the opposite direction. `Family` has no `visibility`
enum at all and `FamilyPolicy#show?` returns true unconditionally, so every
save to a family description is instantly world-visible with no way to stage
it.

## What this is not

This is not a versioning or audit feature. `recordHistory` (PR #103, live
2026-08-06) already covers that. The two are deliberately separate systems
with opposite invariants:

| | history | draft |
| --- | --- | --- |
| mutability | immutable, append-only | mutable |
| cardinality | every change, forever | one, transient |
| purpose | what the public saw | what the public has not seen yet |

Storing drafts in PaperTrail was considered and rejected. See
"Rejected: PaperTrail as draft storage" below.

## Prior art

Three established patterns, all of which separate a live copy from a working
copy:

- **Document pair.** Sanity keeps a second document whose id is prefixed
  `drafts.`. Editing a published document copies it into a draft sibling;
  publishing copies the draft over the published id and deletes the draft.
  Drafts are invisible to unauthenticated readers.
  <https://www.sanity.io/docs/content-lake/drafts>
- **Live row plus revision store.** Wagtail keeps the live row as published
  truth and puts edits into `Revision` rows, tracked by `live_revision`,
  `latest_revision`, and `has_unpublished_changes`. Only Publish touches live.
  <https://docs.wagtail.org/en/stable/topics/snippets/features.html>
- **Stage and Live tables.** Silverstripe materialises both, and names the
  resulting states: Not Yet Published, Published, Draft (published but with
  newer draft changes awaiting publication), Unpublished.
  <https://docs.silverstripe.org/en/6/developer_guides/model/versioning/>

For the read API, the standard shape is a lens rather than new types.
Contentful splits one schema across a Content Delivery API (published) and a
Content Preview API (drafts). Sanity uses a single API with a *perspective*
selecting whether in-flight changes are applied. Neither exposes drafts as
separate objects for clients to merge.
<https://www.sanity.io/docs/content-lake/perspectives>

No maintained Rails gem exists for this. Draftsman last shipped 0.7.2 in April
2018 against ActiveRecord 4/5, wants integer `draft_id` columns (we are uuid
throughout), and its README currently asks for a new steward. DraftPunk is not
published to RubyGems. Hand-rolling is the only option, which is consistent
with Wagtail and Sanity building this into their cores: draft/publish is
tightly coupled to a project's own authorization and read paths.

## Decisions

### Storage: a separate pending-changes table

The live row is never touched by editing. A `record_drafts` row holds the
working copy. Publishing does not replay through the mutation layer: the
shipped `Drafts::Publisher` loads the live record, applies the draft's staged
values onto it in memory through `Drafts::Overlay` (which owns the
translations-container merge semantics), explicitly applies the family-name
mirror and the publication-state flip, then saves once. See "Publish,
conflict, discard" below for the mechanism in full.

Rejected alternative, **shadow row** (a draft as a real row in `plants` with a
`draft_of_id` self-FK): every existing validation, resolver, and form would
work unchanged, but it injects rows that must never be seen into the exact
tables every public read path queries. Every resolver, every Pundit scope, the
dependency counts in `SoftDeletePlant`, and the mobile contract become places a
draft can leak. A separate table makes that failure structurally impossible
rather than a matter of vigilance.

Rejected alternative, **per-locale publication state**: solves the translation
case precisely and would allow an English typo fix to publish while Swahili
stays pending, but it means restructuring the Mobility container blob the
frozen mobile contract reads, and it does nothing for scalar or range fields.
A separate drafts table degrades into this later if wanted: locale scoping
becomes a column on `record_drafts` rather than surgery on `plants`.

### Rejected: PaperTrail as draft storage

The originating idea, and worth recording why it fails here:

- `versions.object` holds the state *before* a change. There is no version row
  representing "current", so a draft would have to be written as a version that
  never corresponded to a real saved state: a lie in an append-only audit log.
- `recordHistory` and `restorePlantVersion` are live in production. Draft saves
  would appear in the history drawer as edits that never happened, and restore
  would happily restore a draft that was never published.
- The `object` payload is YAML. Not queryable, so "which records have pending
  drafts" is unanswerable.
- `paper_trail-association_tracking` is not installed, so relation changes are
  invisible to it regardless.

PaperTrail *is* used here, correctly, for conflict detection. See below.

### Scope: fields on the record's own row

Drafts stage the record's own columns, including the `translations` jsonb
container. That covers the originating complaint in full, since every locale
lives in that column.

Not staged: relations (categories, tolerances, growth habits, antinutrients),
common names, images, life-cycle events. Those write through to live
immediately, as today.

`plants.family_id` is an ordinary column and is therefore staged. Note that
`Mutations::Concerns::FamilyAssignment` mirrors `family.name` into the legacy
`family_names` column when blank; that mirror must also run on publish, but
`FamilyAssignment` is mutation-layer code that publish does not go through.
The shipped `Drafts::Publisher` reproduces the mirror explicitly
(`apply_family_names_mirror`), keyed on the draft having staged `family_id`
at all, immediately after applying the overlay and before the single save.

### Entities: Plant, Variety, Family, Category

Selected by the rule "has translatable fields, and has an editing surface worth
staging".

| model | translatable | included | why |
| --- | --- | --- | --- |
| Plant | yes (30+) | yes | originating case |
| Variety | yes | yes | same surface as Plant |
| Family | `description`, `seed_banking_notes` | yes | no visibility enum at all, so today every save is instantly public |
| Category | `name`, `description` | yes | after detail-page promotion, see Sequencing |
| Specimen | none | no | operational data |
| Location | none | no | operational data |
| Tolerance / GrowthHabit / Antinutrient / ImageAttribute | yes | no | super-admin lookups with no visibility state to lose |
| Image | yes | no | edited in a dialog, no room for the workflow |

The table is polymorphic, so adding an entity later is a migration-free change.

### One draft per record, organization-wide

One draft per record, enforced by a unique index on
`(draftable_type, draftable_id)` rather than by convention. Sanity, Wagtail,
and Draftsman all ship this constraint.

Anyone who can edit the record can see and edit its draft. Author and
last-editor are displayed so nobody trips over a colleague's work blind.

Known limitation, accepted: an editor cannot publish an urgent one-field fix
without also publishing whatever else is pending in the draft. With current
team size this is rare, and nothing is ever lost because `recordHistory`
provides restore. Relaxing to multiple named drafts later means dropping the
unique index and adding a name column.

### There is only one thing called "draft"

An earlier draft of this design had two editing mechanisms: never-published
records editing the row directly, published records editing a pending row.
That was rejected because editing behaviour would silently change the first
time a record was published.

Instead the rule is unconditional: **the editor always edits the draft, and
Publish always applies the draft to live.**

- `plants` row = the published version. It may not be visible yet, but that is
  what it is.
- `record_drafts` row = the working copy. Created on first edit, destroyed on
  publish or discard.
- `publication_state` = whether the published version is visible.

So "draft" as a noun refers to exactly one object, the working copy. The
status badge "Draft", meaning no published version exists yet, is consistent
with it: such a record's only real content *is* its draft.

Creation is not editing, and is the one place the rule does not apply: a new
record's initial values land on the row via `createPlant`, and the draft
appears on first edit. See "Create defaults" for why. This is invisible to
editors, who never see a record without opening it, at which point every
record behaves identically.

### Status is derived, never stored

Wagtail stores `has_unpublished_changes`. We do not need to; the draft
metadata field is null or not, and `publication_state` and `deleted_at`
already exist.

| `publication_state` | draft exists | `deleted_at` | shown as |
| --- | --- | --- | --- |
| `draft` | either | null | Draft |
| `published` | no | null | Published |
| `published` | yes | null | Published — edited |
| any | either | set | Deleted |

Accepted simplification: Silverstripe distinguishes "Not Yet Published" from
"Unpublished" (withdrawn after having been published). We do not. Nothing in
the schema records that a record was once published, and adding a column would
contradict the derive-do-not-store decision for the sake of a label. A
withdrawn record therefore shows as Draft. If this proves confusing, a
`first_published_at` timestamp set on first publish would enable the
distinction without changing anything else in this design.

### Create defaults

Draft is the default where creation is explicit (the admin SPA's create
dialog), not a mandate. A caller may set state at creation and bypass it.

The mobile contract is **not** changed. `spec/contracts/mobile_writes_contract_spec.rb:196`
(`addCustomPlant`) sends no `visibility`, so it falls through to the column
default `visibility integer DEFAULT 0` (`private`). That behaviour stays
exactly as it is. `private` maps to `{published, organization}` and is not
publicly visible, so nothing leaks.

A new record's first content lands on the row via `createPlant`; the draft
appears on first edit. This keeps `CreatePlant` and its contract untouched, and
is invisible to editors because they never see a record without opening it, at
which point everything is uniform.

### Publish is not the same as making public

`publication_state` says whether a record is published; `access_level` says to
whom. Publishing a never-published record created as Draft yields
`{published, organization}`, which is legacy `private` and not publicly
visible.

Rather than hide that, the first publish of a record opens a small dialog:
"Publish to organization" or "Publish publicly", defaulting to organization.
Subsequent publishes apply changes with no dialog.

## API design

### Reads: a perspective lens

```graphql
plant(id: ID!, perspective: Perspective = PUBLISHED): Plant
```

`Perspective` is `PUBLISHED | DRAFT`. Under `DRAFT` a service applies the
draft's `data` onto the loaded record in memory and never saves it, the same
way `ChangeHistory::Restorer` reifies a version. `PlantType` gains no fields.

Anonymous and mobile callers never pass the argument, so they cannot receive
draft content. This is the leak-prevention mechanism and it requires nobody to
remember anything.

`perspective: DRAFT` calls `authorize record, :update?`. A reader holding only
`show?` receives published content, not an error.

This is the codebase's second read lens; `language:` setting `Mobility.locale`
is the first, so the pattern already exists in the resolvers.

### Draft metadata

One field on the four draftable types, null when no draft exists:

```graphql
type RecordDraftInfo {
  updatedAt: ISO8601DateTime!
  author: String!
  lastEditor: String!
  changedFields: [String!]!
  isStale: Boolean!
}
```

`changedFields` is `data.keys`, which is why storing only changed keys pays
off: it drives the changed-field markers, the history-drawer entry, and the
conflict dialog with no extra work.

### Writes: reuse the existing mutations

- `saveAsDraft: Boolean` on `updatePlant`, `updateVariety`, `updateFamily`,
  `updateCategory`. Every existing argument, `RangeLiteralValidation`, and
  `FamilyAssignment` stay in one place.
- `publishDraft(recordId: ID!)`
- `discardDraft(recordId: ID!)`

Two typed mutations rather than four pairs; they take a Relay global ID and
dispatch on the decoded type.

The API deliberately **retains** the ability to write live directly.
`SourceSynchronizer`, the importers, and the mobile app need it. "Live is only
touched by Publish" is an editing-UI policy, not an API restriction. This
matches Contentful and Sanity, and is why the mobile app keeps working
untouched.

### Lists

List resolvers gain a `hasPendingChanges: Boolean` filter, and rows gain an
"edited" badge. Without a way to find drafts the feature quietly accumulates
orphans.

List resolvers do **not** take `perspective`. Lists always show published
content plus the badge. Draft content is only ever reachable through a
single-record query, which keeps the surface where draft data can escape down
to one code path.

List draft metadata must be batch-loaded by `(draftable_type, draftable_id)`,
not resolved per row. See `perf-plants-nplusone` for why this repo takes N+1
seriously.

## Data model

`record_drafts`:

| column | notes |
| --- | --- |
| `id` | uuid, `gen_random_uuid()` |
| `draftable_type` / `draftable_id` | polymorphic; `draftable_id` is uuid |
| `data` | jsonb, changed keys only, model attribute names |
| `base_updated_at` | live row's `updated_at` at draft **creation**; the conflict anchor. Never advanced by subsequent draft saves, or a conflict arriving mid-draft would be silently swallowed. Advanced only by an explicit confirm-and-publish or a future "accept live changes" action |
| `author_principal_id` | uuid, FK to `principals` |
| `last_editor_principal_id` | uuid; org-wide editing means these diverge |
| `created_at` / `updated_at` | |

Unique index on `(draftable_type, draftable_id)`.

Two requirements that fail silently and therefore need their own tests:

- **`RecordDraft` must opt out of PaperTrail.** `ApplicationRecord` calls
  `has_paper_trail` unconditionally, so without an explicit opt-out every draft
  save writes an audit version, flooding the log this design exists to protect.
- **`data` uses model attribute names, not GraphQL argument names.**
  `translations` is one key holding the whole Mobility container blob. The
  permitted-key whitelist derives from the same constants
  `ChangeHistory::Restorer` uses (the `EditableArguments` concerns plus
  `scientific_name`, `family_names`, `family_id`, `translations`) so the two
  cannot drift.

## Publish, conflict, discard

### Publish

In a transaction, with `with_lock` on the record:

1. Re-run conflict detection. The check at dialog-open time is advisory; this
   one is authoritative.
2. Apply `data` onto the loaded record in memory through `Drafts::Overlay`
   (not by replaying it through a mutation or `record.update`), then
   explicitly apply the family-name mirror. Validations, the
   `OrganizedResource` dual-write, and PaperTrail all still run, because they
   are triggered by the single `save!` in the next step, not by the update
   path itself.
3. If `publication_state` is `draft`, flip it to `published` (also applied
   explicitly, not via the mutation layer).
4. Save once, then destroy the draft.

One PaperTrail version results, whose changeset is the real before/after. The
history drawer stays a record of what the public actually saw.

On validation failure: payload errors in the existing style, and **the draft
survives**. A failed publish must never lose work.

Publishing an unchanged draft is a no-op, not an error.

### Conflict detection

Take the PaperTrail versions since `base_updated_at`, union their changeset
keys, intersect with `data.keys`. Non-empty means a real conflict.

A coarse `live.updated_at > base_updated_at` check was rejected: it fires on
every `SourceSynchronizer` run touching `last_synced_at`, which trains editors
to click through warnings.

Reuses `ChangeHistory::DiffBuilder`, including its existing handling of
changesets carrying enum strings when the item row exists but raw integers on
destroy/orphaned versions. The conflict dialog shows live's value beside the
draft's for the contested fields only. Confirm to publish anyway, or discard.
No merge UI.

Writers that can move live under a draft, all covered by this check:
`SourceSynchronizer` (its `DENY_LIST` already protects `publication_state`,
`access_level`, and `deleted_at`, so it cannot corrupt workflow state, but it
can change a staged field), `ChangeHistory::Restorer`, mobile, and direct API
callers.

### Discard and delete

Discard requires the same permission as editing and is confirmed, since the
draft was never versioned and cannot be recovered.

Soft-deleting a record keeps its draft; restore brings both back.

## SPA design

One module, `src/features/drafts/`:

- `api.ts` — `useSaveDraft`, `usePublishDraft`, `useDiscardDraft`, query-key
  invalidation
- `useDraftState.ts` — composes perspective and draft metadata for a detail page
- `DraftBanner.tsx` — status, author, last-edited time, Publish / Discard
- `PublishDialog.tsx` — first-publish access-level choice, and the stale-draft
  conflict display
- `PendingDraftCard.tsx` — the history-drawer entry

Then four thin integrations into `PlantDetailPage`, `VarietyDetailPage`,
`FamilyDetailPage`, and `CategoryDetailPage`.

**Tripwire: if any of the four needs bespoke draft logic, the abstraction is
wrong.** Reviewers should hold the implementation to this.

### Mechanics

View mode defaults to `perspective: PUBLISHED`, what the public actually sees,
with a Published / Draft toggle when a draft exists. Edit mode always requests
`DRAFT`.

Save writes `dirtyValues(form)` to the draft, which maps one-to-one onto
`data`'s changed-keys design. `useDirtyNavigationGuard` is unchanged. Explicit
Save Draft, no autosave, so a draft cannot appear because someone clicked into
a field.

Changed fields get a marker from `draft.changedFields`, so an editor opening a
colleague's draft can see what has been touched.

### History drawer

`HistoryDrawer` adds `draft { ... }` to its existing `recordHistory` query and
renders `PendingDraftCard` above the newest version: visually distinct,
labelled pending, showing changed fields, clicking through to edit.

`DiffTable` renders a PaperTrail changeset; a draft diff is draft-versus-live,
not a changeset, so it needs a small adapter. Named here so it does not become
a duplicate component.

## Testing

API:

- perspective isolation: anonymous callers, and callers omitting the argument,
  can never receive draft content
- `RecordDraft` writes no PaperTrail versions
- the one-draft-per-record unique index holds under concurrent creation
- publish under conflict
- publish with validation failure leaves the draft intact
- `spec/contracts/mobile_*` passes untouched, as the regression proof

SPA: component tests per banner state, publish dialog, conflict dialog; one
e2e covering edit, save draft, verify live unchanged, publish, verify live
updated.

## Sequencing

Two projects, in order.

1. **Category detail-page promotion.** Category is the only content entity
   still edited entirely in a modal. Everything else uses a create-and-go
   dialog collecting the minimum to create the record, then navigating to a
   detail page. Category needs a `categories.$categoryId` route,
   `CategoryDetailPage`, `CategoryView`, Overview and Translations tabs, and a
   slimmed create dialog. Independently valuable, and a precondition for
   Category getting drafts on equal footing. Not about drafts, so it ships
   separately.
2. **Draft and publish**, as designed above.

## Considered and deferred: staging relations

Recorded so the next person to notice `paper_trail-association_tracking` does
not re-litigate this.

**The gem is not the mechanism, and should not be adopted.** Drafts live in
`record_drafts.data`, not in PaperTrail, so staging relations means putting
`category_ids: [...]` in a jsonb blob. The gem is irrelevant to that. It should
not be adopted on its own merits either:

- Its README recommends `active_snapshot` instead, calling itself "mostly a
  blackbox solution which encourages you to set it up and then assume it just
  works, which can make for major data problems later."
- It documents incompatibility with transactional tests (our whole suite) and
  with STI (our life-cycle events), the latter tracked as
  <https://github.com/paper-trail-gem/paper_trail/issues/594>.
- Its purpose is already served here. `VersionedUnderRoot` is applied to all
  seven join models plus `CommonName` and `Image`, stamping `{root_type,
  root_id}` into each child version's metadata so the aggregated history picks
  them up with one GIN-indexed containment lookup. Relation, common-name, and
  image changes already appear in `recordHistory`. The gem would duplicate a
  working mechanism.

**Staging relations is deferred, not rejected.** The three unstaged groups
differ sharply in cost:

- Relation sets (4 on plant, 3 on variety) are cheap to write (id arrays,
  published by replaying the existing `UpdateRelations*` mutations) but the
  perspective overlay would have to override association readers on an
  in-memory record, which is where the design gets muddy.
- Common names are medium-hard: rows with their own translations, primary
  flags, and four mutations; staging means an intended set with synthetic ids.
- Images are hard and probably wrong to stage. Uploads PUT to S3 before any DB
  record exists, so a discarded draft orphans S3 objects and needs a reaping
  story.

Deferring is safe because it is not a one-way door: `data` is schemaless jsonb
so relation keys need no migration, publish already replays through existing
mutations, and the perspective overlay would be extended rather than
redesigned.

It is also substantively right. Staging earns its cost for things with a
half-finished state. A 2,000-word translation has one; "add tolerance:
drought" is a single atomic click.

Accepted cost: an editor preparing a revision who also adds two categories
sees the categories go live immediately while the text waits. The changed-field
markers make this legible, but it is the most likely source of a "why did that
publish?" question.

## Explicitly out of scope

- autosave
- scheduled publishing
- multiple named drafts per record
- staging of relations, common names, images, or life-cycle events
- three-way merge UI
- an API-level ban on direct live writes
- drafts for Specimen, Location, Image, or the lookup tables
