# Botanical families: design

Status: approved design, not yet implemented.
Date: 2026-08-05.
Closes: ECHO_Plant_API#83 ("Establish a table of Plant Families").

## 1. What we are building

A `families` table holding a locked, externally-sourced list of botanical,
fungal and algal families; a `belongs_to` from `Plant`; editable metadata that
ECHO owns on top of the locked list; and the GraphQL and admin surfaces to read
and edit it. Nothing that already works may change behaviour.

The list is immutable through the API. Only the metadata is editable, and only
at plant trust level 9.

## 2. Decisions

These were settled with the product owner before implementation. Do not
re-open them without a reason that is new evidence, not preference.

| Decision | Value |
|---|---|
| Source | Catalogue of Life, single source |
| Release | COL Extended Release (XR), pinned by version |
| Kingdoms | Plantae, Fungi, Chromista |
| Cardinality | one family per plant (`belongs_to`) |
| Metadata editing | plant trust level 9 (`admin?`) |
| List mutation | impossible through the API, enforced in model and database |
| Refresh | manual rake task, prints a diff, requires confirmation |
| Existing data | reconciled with a human review step |
| Own synonym table | out of scope |
| `familyNames` | unchanged and still writable; see section 10 |
| Issue #83 seed-banking metadata | in scope for this pass |

### 2.1 Why Catalogue of Life and not GBIF

The original brief specified the GBIF Backbone Taxonomy. Investigation found
that the GBIF Backbone **was last built 2023-08-28 and its build process is
discontinued**; GBIF itself migrated to Catalogue of Life Extended Release.
Verified two ways: the dataset record still reports `pubDate: 2023-08-28`, and
the hosted-datasets directory contains build folders only for 2021-11-26,
2022-11-23 and 2023-08-28.

A refresh task pointed at the Backbone would report "no changes" forever, which
makes the "refreshable from GBIF" requirement unsatisfiable as written. The
source was therefore changed to Catalogue of Life, which publishes monthly and
ships per-release diff files.

COL is also the more accurate vocabulary for our purposes. Every family merge
GBIF gets wrong, COL gets right:

| Name | GBIF | COL |
|---|---|---|
| Tiliaceae | accepted, standalone | synonym of Malvaceae |
| Durionaceae | accepted, standalone | synonym of Malvaceae |
| Asclepiadaceae | accepted, standalone | synonym of Apocynaceae |
| Chenopodiaceae | synonym of Amaranthaceae | synonym of Amaranthaceae |
| Guttiferae | synonym of *Hypericaceae* | synonym of **Clusiaceae** |

The Guttiferae case matters: ICN Art. 18.5 pairs Guttiferae with Clusiaceae, so
GBIF disagrees with the nomenclatural code and COL does not.

### 2.2 Why one family per plant is safe

The concern raised against `belongs_to` was that reclassification produces
contested placements that a single foreign key cannot express, citing
`Malvaceae  Bombacaceae   Durionaceae` in live data.

Tested against COL, all four multi-family strings in production collapse to a
single accepted family, because Bombacaceae and Durionaceae are both synonyms
of Malvaceae. Zero production records require a human choice between two
families. The objection does not survive contact with the data.

## 3. Findings that shaped this design

Recorded because each one changed a decision, and because several contradict
the original brief.

1. **Mobile writes `familyNames`, it does not only read it.** `CreatePlant` and
   `EditPlant` bind it to a single-line `TextInput`; the offline sync engine
   plumbs it from the GraphQL response through a SQLite `TEXT` column, into UI
   state, and back out as mutation input. No consumer anywhere splits, joins or
   parses it. This rules out freezing the field read-only.
2. **The mobile full sync is unpaginated.** `getAllPlants` calls
   `plants(language: ...)` with no `first:` and reads `nodes` directly. A global
   `default_max_page_size` would silently truncate it. Do not add one.
3. **COL identifiers are not stable.** COL's own policy forces an ID change when
   a name flips between accepted and synonym, which is exactly what a merge is.
   Empirical sampling found roughly 30% of family IDs changed over five years,
   including mainstream families such as Brassicaceae. The stable key for a
   family is its **name**, not its COL ID.
4. **Only `categories` among the lookup tables carries ownership columns.**
   `tolerances`, `growth_habits`, `antinutrients` and `image_attributes` are
   bare reference tables. Families follows those, not `categories`.
5. **Trust level 10 has no members.** A production audit on 2026-08-03 found
   exactly one account at plant trust >= 9 and zero at >= 10. Gating family
   metadata at 10, as the other lookups do, would ship it uneditable by anyone.
   Level 9 is the only tier with a live human in it.
6. **`plant_data_translation` is dormant and irrelevant.** It is a Weblate
   export from the pre-2020 `Resource` model, last pushed 2022-03, referenced
   nowhere in this repo. New translatable fields need no pipeline work.
7. **`pdf-service` is not a consumer of this API.** It queries
   `www.echocommunity.org/graphql`, a different application whose separate
   legacy `Plant` model happens to share the column name `family_names`.

## 4. Schema

```sql
CREATE TABLE families (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                   varchar NOT NULL,
  col_id                 varchar,
  kingdom                varchar NOT NULL,
  plant_type             varchar,
  status                 varchar NOT NULL DEFAULT 'accepted',
  superseded_by_id       uuid REFERENCES families(id),
  classification_source  varchar NOT NULL,
  classification_version varchar NOT NULL,
  snapshot_date          date    NOT NULL,
  storage_physiology     varchar,
  seed_longevity         varchar,
  seed_banking_rank      integer,
  translations           jsonb   NOT NULL DEFAULT '{}',
  created_at             timestamp(6) NOT NULL,
  updated_at             timestamp(6) NOT NULL
);

CREATE UNIQUE INDEX index_families_on_lower_name ON families (lower(name));
CREATE UNIQUE INDEX index_families_on_col_id ON families (col_id) WHERE col_id IS NOT NULL;
CREATE INDEX index_families_on_status ON families (status);
CREATE INDEX index_families_on_plant_type ON families (plant_type);
```

And on plants:

```sql
ALTER TABLE plants ADD COLUMN family_id uuid REFERENCES families(id);
CREATE INDEX index_plants_on_family_id ON plants (family_id);
```

Notes on specific columns:

- **`name` is the natural key**, unique case-insensitively. This is what makes
  the table survive COL identifier churn (finding 3). Family names are stable;
  their taxonomic status is what moves.
- **`col_id` is a refreshable attribute, never a key.** Nothing references it.
- **`plant_type`** is derived from COL's own `group` field, not hand-curated.
  See section 8.2.
- **`status` / `superseded_by_id`** support merges without dangling references.
  A superseded family keeps its row and its plants until a human approves the
  repoint. See section 9.
- **Translated fields are `description` and `seed_banking_notes`** only, via
  Mobility's container backend. The scientific name is never translated;
  `Fabaceae` is `Fabaceae` in every locale.
- Families deliberately carries **no ownership columns** and does **not**
  include `OrganizedResource`. It is reference data: nothing owns it, there is
  no draft state, and nothing to soft-delete. `OwnedResourcePolicy#create?`
  grants creation to any trust-2 writer, which is the opposite of an immutable
  list, so inheriting it would have to be undone anyway.

### 4.1 Enumerations

`plant_type`, derived from COL `group`:

| COL group | plant_type | Families |
|---|---|---:|
| angiosperms | Angiosperms | 463 |
| gymnosperms | Gymnosperms | 47 |
| pteridophytes | Ferns & Fern Allies | 127 |
| bryophytes | Mosses, Liverworts & Hornworts | 253 |
| algae | Algae & Seaweed | 862 |
| protists | Protists | 1357 |
| ascomycetes, basidiomycetes, otherfungi, fungi, pseudofungi | Fungi | 1342 |
| plants | Other Plants | 114 |
| eukaryotes | Other | 31 |

Verified: this maps **100% of the 4,596 accepted families**, with no unmapped
rows.

`storage_physiology`: `orthodox`, `recalcitrant`, `intermediate`, `variable`,
`mixed`, `unknown`.

`seed_longevity`: `low`, `low_medium`, `medium`, `medium_high`, `high`.

`seed_banking_rank`: integer 1 to 5, validated inclusive.

## 5. Authorization

```ruby
class FamilyPolicy < ApplicationPolicy
  def index? = true
  def show?  = true

  def update?
    user&.admin?   # plant trust >= 9
  end
end
```

`create?` and `destroy?` are deliberately **not defined**, so they inherit
`ApplicationPolicy`'s `false`. That is the precise expression of "the list is
immutable, only the metadata is editable": there is no code path to add or
remove a row, and it cannot be re-enabled by accidentally exposing a mutation.

Reads are unconditionally public, matching the other lookup tables.

## 6. Immutability enforcement

The requirement is enforcement at the model or database level, not merely the
absence of a mutation. Both layers are implemented.

**Model.** `Family` refuses creation and destruction outside an explicit
importer block:

```ruby
Family.importing { ... }   # the only context in which writes to the list occur
```

Outside that block, `before_create` and `before_destroy` abort. Metadata
updates are unaffected; only the identity columns are frozen.

**Database.** A trigger refuses `INSERT` and `DELETE` unless the importer has
set a session variable. This is the codebase's first trigger; there is one
existing precedent for raw DDL in a `reversible` block
(`organizations_kind_shape`, a CHECK constraint), and the trigger follows that
shape. It is deliberate: a model guard alone can be bypassed by
`insert_all`, `delete_all`, or a console session.

## 7. GraphQL surface

New, all additive:

- `family(id:, language:)` - single family by Relay global ID.
- `families(...)` - paginated connection, filterable by `name`, `kingdom` and
  `plantType`, following the existing lookup resolver pattern.
- `Family.plants` - paginated connection of plants in the family, policy-scoped.
- `Plant.family` - the new relation.
- `updateFamily` - metadata only. Accepts `description`, `seedBankingNotes`,
  `storagePhysiology`, `seedLongevity`, `seedBankingRank`, and `language`.
  It accepts no `name`, no `colId` and no `kingdom`.

Explicitly **not** built: `createFamily`, `deleteFamily`. The shared
`Mutations::Lookups::` base classes are not used, because they come as a
create/update/delete trio and the shared spec generator assumes all three
exist. `UpdateFamily` is written directly against `BaseMutation`.

`Plant.familyNames` is unchanged: same type, same nullability, same
writability, no deprecation marker. See section 10.

### 7.1 Performance

- `Family.plants` declares a per-field `max_page_size`. Fabaceae will eventually
  hold roughly 2,200 plants and today already holds 100.
- A **global** `default_max_page_size` must not be added: it would truncate the
  mobile full sync (finding 2). `max_depth` and `max_complexity` are worth
  adding but belong in a separate, independently tested change, because they
  can also break unpaginated clients.
- `PlantsResolver` gains `family` to its `includes` so a plant list does not
  issue one query per row. `Family.plants` preloads in the same way.
- `totalCount` on any connection issues a `COUNT(*)` over the whole scope. That
  is pre-existing behaviour across every list in the schema, and is acceptable
  at family cardinality, but should not be made worse.
- `families` is small enough (4,596 rows) that the absence of a GIN index on
  `translations` does not matter. No new index convention is introduced.

## 8. Seeding

### 8.1 Source and version pinning

Dataset: Catalogue of Life Extended Release, ChecklistBank dataset key
`315834`, alias `COL26.7 XR`, issued 2026-07-17.

Every row records `classification_source = 'catalogue-of-life'`,
`classification_version = 'COL26.7 XR'` and `snapshot_date = 2026-07-17`, so we
always know exactly what was loaded.

Enumeration recipe, verified live:

```
GET https://api.checklistbank.org/dataset/315834/nameusage/search
    ?rank=family&status=accepted&TAXON_ID={P|F|C}&limit=1000&offset=N
```

Maximum `limit` is 1000. Counts: Plantae 1,375, Fungi 1,309, Chromista 1,912,
for **4,596 accepted families**.

The API requires a browser-like `User-Agent`; a bare curl is refused by a bot
wall on the download host.

Licence is CC-BY 4.0. The citation string is recorded in the seed task output
and in the repository docs.

### 8.2 Deriving plant_type

Use COL's `group` field, not a hand-written lineage mapping. An initial attempt
to derive the grouping from `phylum` and `class` left 4.26% unmapped and, worse,
misclassified **78 monocot families** (`Liliopsida`) as unknown when they are
plainly angiosperms. COL's own `group` field already accounts for them: its
`angiosperms` count of 463 is exactly the 385 dicot plus 78 monocot families.

### 8.3 Bulk loading

The existing seed convention inserts lookup rows one at a time through
ActiveRecord. At 4,596 rows with Mobility callbacks that is needlessly slow, and
there is no existing bulk-insert precedent in the codebase. The seeder uses
`upsert_all` keyed on `lower(name)`, which is also what makes the refresh task
idempotent. This is a deliberate, documented departure from the existing
one-row-at-a-time seed style.

## 9. Refresh task

`rake families:refresh` fetches a target COL release, diffs it against the
current table, prints what would change, and applies nothing without
confirmation. `DRY_RUN` defaults to on, following `ownership.rake`.

The governing rule: **the refresh task never silently repoints a plant.**

| Upstream event | Detection | Action |
|---|---|---|
| **New family** | in release, not in table | insert, report count |
| **Rename** | our name absent from accepted set; present as synonym whose accepted name is new | update `name` in place, keep our UUID, so every plant link survives |
| **Merge** | our name now a synonym of another accepted family | do **not** auto-repoint. Report "N plants reference A, now a synonym of B". On confirmation, repoint plants to B and set A `status='superseded'`, `superseded_by_id=B`. A's row is kept so nothing dangles |
| **Split** | our name gone; several new accepted families under the same parent | cannot be resolved automatically, because which plant belongs in which successor is a per-plant taxonomic judgement. Report every affected plant, leave them on A, flag A for review. Never guess |
| **Disappears, no successor** | our name absent, no synonym target | report, change nothing |

COL publishes `created.tsv`, `deleted.tsv`, `resurrected.tsv` and
`unstable.txt` per release, plus a changelog with family-count deltas. These are
the fast path. One caveat found during investigation: a historical diff file
downloaded successfully, but no current release's diff URL resolved, so **the
task must be able to fall back to comparing two releases through the API** and
must not depend on the diff files being present.

Family churn is real and worth expecting: COL's 2026 monthly releases moved
family counts by -12, +19, -10, -6 and -2.

## 10. `familyNames` backward compatibility

`familyNames` is a plain nullable `String` on `Plant`. It is not translated
(verified: passing `language:` does not change it, while `primaryCommonName` on
the same record does change). It is read **and written** by the frozen mobile
app, the admin SPA, and the contract specs.

The agreed path, in order:

1. **Now.** `familyNames` is untouched: same column, same type, same
   nullability, still writable by every client. Existing queries return
   byte-identical results. No deprecation marker.
2. **Now.** When a client sets `familyId` and `family_names` is **blank**, the
   canonical family name is written into `family_names`. Human-typed text is
   never overwritten.
3. **Later.** Once the mobile app and SPA replace the free-text control with a
   family selector, `familyNames` is marked deprecated.
4. **Later still.** It is removed.

Steps 3 and 4 are out of scope for this pass and depend on a mobile release,
which only the app's external developer can ship.

## 11. Reconciling the existing plants

322 production plants, 86 distinct `family_names` values.

**Pipeline.** Normalise the free text, look the result up in COL, and only if
that fails ask GBIF for a *corrected spelling*, which is then re-resolved
through COL. The final answer always comes from COL; GBIF never decides which
family a name belongs to, only how it should be spelled. COL has no fuzzy
matching at all, which is why the GBIF step exists.

Normalisation must handle, all present in real data: en dashes (U+2013, used in
every "common name appended" record and never an ASCII hyphen), literal tabs,
leading and trailing whitespace, runs of two or more spaces used as a delimiter,
parentheses, commas, and the words "Or" and "and".

**A kingdom and rank guard is mandatory.** Without it the typo `Fabacaea`
resolves to **Hiatellidae, a bivalve mollusc**, at confidence 0. A confidence
threshold alone cannot save you: the correct recovery of `Curcurbitaceae` to
Cucurbitaceae comes back at confidence 5.

**Result:**

| Outcome | Plants |
|---|---:|
| Auto-resolved by COL | 283 |
| Auto-resolved after a high-confidence spelling fix | 9 |
| Blank source field, left null | 22 |
| Requires a human decision | 8 |

292 applied, 8 for review, 22 left null. 297 plants resolve to exactly one
family: the 292 applied, plus 5 of the 8 review cases that have a suggested
family awaiting approval. Those 297 span 52 distinct families. Fabaceae rises
from 76 raw occurrences to 100 once its six spellings merge.

The eight review cases are all decidable against the plant's own binomial:
two `Leguminaceae` and one `Fabacaea` on *Acacia*, *Aeschynomene* and
*Sesbania* (all legumes, so Fabaceae); two `Curcurbitaceae`; one `Bignonias` on
*Pyrostegia venusta*; one `Acanthus` on *Trichantera gigantea*; and one
`Fabaceae, Legumininosae` on *Trifolium pratense*.

The task writes a reviewable report and applies nothing until approved.

## 12. Issue #83: seed-banking metadata

Issue #83 supplies two spreadsheets. The second is genuine family-level
guidance and is the first real content for the "metadata we add on top".

**Loaded:** `Storage Physiology`, `Longevity`, `Suitability Notes` and
`Ranking`, for 347 families. These become `storage_physiology`,
`seed_longevity`, the translatable `seed_banking_notes`, and
`seed_banking_rank` respectively.

**Not loaded:** `Seed Size & Handling` and `Dormancy & Germination`. Both are a
single value for 303 of 347 rows ("Variable" and "Varies by species"), so they
carry almost no information. They can be added when they have real content.

**Not stored, deliberately:** the `Count` column from the first spreadsheet. It
is a count of FPI food plants per family, so it would be stale on write and it
excludes ECHO's own plants entirely. It is served instead by `totalCount` on the
`Family.plants` connection, which is always correct for whatever data exists.

**`Plant Type` is derived from COL rather than loaded** (section 8.2). The
spreadsheet column has 14 values with overlaps such as `Moss` alongside
`Mosses, Liverworts, Hornworts`, and it only covers 624 families.

### 12.1 Data issues in the source files

- **Poaceae and Rutaceae each appear twice** in the first spreadsheet (897 and
  1; 262 and 4). A naive load would create duplicates and undercount both.
- **`Longevity` has the same dash bug as the plants data**: `Low–Medium`
  (en dash, 86 rows) and `Low-Medium` (hyphen, 23) are one value split in two.
  Merged, it is the largest bucket at 109.
- `Storage Physiology` has 4 clean values covering 317 of 347 rows, plus 20
  hedged or parenthetical variants such as `Mostly orthodox (onions, garlic,
  leeks)`. The loader maps these to the enum and **preserves the parenthetical
  qualifier in the notes**, so no editorial content is silently discarded.
- `Incertae sedis` is a placeholder, not a family, and is skipped.

### 12.2 Families in the spreadsheets that cannot exist in a locked COL list

Of 623 real family names, 615 are accepted in COL. Eight are not:

| Name | COL | Has seed-banking data |
|---|---|---|
| Chenopodiaceae | synonym of Amaranthaceae | yes |
| Pomaceae | not found | yes |
| Cystoseiraceae | synonym of Sargassaceae | no |
| Exidiaceae | synonym of Auriculariaceae | no |
| Melanogastraceae | synonym of Paxillaceae | no |
| Nostochopsidaceae | synonym of Hapalosiphonaceae | no |
| Leuconostocaceae | synonym of Lactobacillaceae | no |
| Lycoperdiaceae | not found | no |

Agreed handling: **metadata for the six synonyms is redirected to the accepted
family**; `Pomaceae` and `Lycoperdiaceae` have no COL target and are reported
for a human decision rather than guessed at. Two of the eight
(Leuconostocaceae, Nostochopsidaceae) are bacteria and cyanobacteria and fall
outside the approved kingdom scope regardless.

## 13. Testing

Baseline before any change: **1936 examples, 0 failures**, 89.66% line coverage.

New coverage, as required by the brief:

- **Immutability**: `Family.create!` and `#destroy` raise outside the importer
  block; the database trigger rejects a raw `INSERT` and `DELETE`; no
  `createFamily` or `deleteFamily` field exists in the schema.
- **Metadata editing**: `updateFamily` succeeds at trust 9, is forbidden at
  trust 2 and trust 1, and is unauthenticated-rejected with no token. Note this
  differs from every other lookup, which require 10.
- **`updateFamily` cannot change identity**: no `name`, `colId` or `kingdom`
  argument exists.
- **Plant relation**: `plant.family`, `family.plants`, null family, and the
  policy scoping of `family.plants`.
- **Reconciliation**: normaliser unit tests for every real-world malformation
  (en dash, tab, multi-space, parenthetical, comma, "Or"); the kingdom guard
  rejecting the Hiatellidae match; the multi-candidate collapse.
- **Backward compatibility**: `familyNames` round-trips unchanged; the
  blank-only mirror writes when blank and does not overwrite when populated.

Existing contract specs under `spec/contracts/mobile_*` must pass untouched.
`schema.graphql` must be regenerated and committed, because CI fails on drift.

Verification that existing queries are byte-identical will be demonstrated, not
asserted: the frozen mobile documents are executed against the schema before and
after and their JSON compared.

## 14. Rollout

**API first, then SPA.** The SPA's codegen runs against a live API schema, so it
cannot be built before the API exists. The SPA also deploys to production
immediately on merge with no gate, while the API deploy is reviewer-gated, so
shipping the UI first would front a nonexistent API. The one precedent for
SPA-first, the category lockdown, was inverted deliberately because it was a
*restriction*, where a stricter UI is harmless; this is an addition, so the
server must lead.

Work happens in isolated worktrees, off the in-flight `ops/s7-repair` and
lookup-pagination branches:

- `.worktrees/api-families` on `feat/families`, from `origin/master`
- `.worktrees/spa-families` on `feat/families`, from `origin/main`

Note that master already contains S7 (`3bd0347`), so the legacy email
authorization layer is gone and authorization is organization membership only.

Admin interface scope: browse families, view their plants, edit metadata and
translations. **No affordance to add, delete or rename.** The picker needs a
typeahead, not a plain select, at 4,596 rows.

### 14.1 Production execution gaps (found in final review)

The numbered deployment sequence with the actual rake-task steps lives in
`docs/superpowers/plans/2026-08-05-botanical-families-api.md` ("Deployment
sequence"), not here; this subsection records the gaps the final
whole-branch review found in it, so they are not re-discovered from scratch:

- **No documented mechanism for running a rake task against production.**
  ECS exec is disabled and production RDS is unreachable from outside the
  VPC, so "on production, run `families:seed`" has no verified procedure
  behind it yet. A one-off `ecs run-task` with a command override on the
  existing task definition is the likely route, but it is unverified and
  must be pinned down (and rehearsed on staging) before the real run --
  flagged as an open operational question, not solved here.
- **Egress**: `families:seed`/`families:refresh` need `api.checklistbank.org`;
  `families:reconcile` additionally needs `api.gbif.org`, both from the ECS
  task's subnet. A blocked COL host fails loudly (retries then raises); a
  blocked GBIF host used to degrade silently to "no suggestion", masked by
  `FamilyResolver#gbif_match` swallowing every error to `nil` -- now logged
  via `Rails.logger.warn`, which is a mitigation, not a fix for the egress
  rule itself.
- **The 8 human-decision reconciliation cases** are never applied by
  `DRY_RUN=0`; they are resolved by hand via `updatePlant(familyId:)` per
  plant, which is safe today (before the SPA ships a picker) because all 8
  have a non-blank `familyNames`, so section 10's blank-only mirror will
  never overwrite it.
- **Rollback**: the schema change is purely additive and `family_id` is
  nullable, so a code rollback with the migrations left in place is safe.
- A post-migration check that the `families_locked_list` trigger actually
  attached belongs between the migration step and the first write.

## 15. Out of scope

Our own synonym table. The Food Plants International import. Any change to how
plants are created or owned. Global GraphQL depth and complexity limits.
Deprecating or removing `familyNames`. Refactoring unrelated code.

## 16. Known risks

1. **COL identifier churn.** Mitigated by keying on name, but a refresh can
   still surface a family whose ID moved with no diff-file warning. The refresh
   task reports rather than guesses.
2. **COL diff files may be unavailable.** A historical file downloaded, but no
   current release's URL resolved. The task must fall back to an API comparison.
3. **Algal coverage.** AlgaeBase was removed from COL over a licensing dispute
   and is confirmed to contribute zero records to the current release. XR
   compensates through ITIS and IRMNG (Chromista 1,912 families, versus GBIF's
   1,858), but depth below family rank may lag a dedicated algal authority.
4. **Protist volume.** 1,357 of the 4,596 families are protists, an artefact of
   including Chromista for algal coverage. The derived `plant_type` lets the
   admin UI filter them out of a picker; excluding them from the seed entirely
   remains an easy, reversible change if they prove to be noise.
5. **No documented COL rate limit.** Back off and retry defensively.
6. **A single multi-family production record** (`Malvaceae  Bombacaceae
   Durionaceae`) collapses cleanly today, but a genuinely two-family record
   would be unrepresentable under `belongs_to`. Accepted.
