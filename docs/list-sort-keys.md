# Scope: sortable columns on the list queries

## Why

Every list query takes `sortDirection: SortDirection = ASC` over a key the
resolver hard-codes, and nothing else:

| Query | Sorted by | Resolver |
| --- | --- | --- |
| `plants` | `scientific_name` | `app/graphql/resolvers/plants_resolver.rb` |
| `specimens` | `created_at` | `app/graphql/resolvers/specimens_resolver.rb` |
| `locations` | `name` | `app/graphql/resolvers/locations_resolver.rb` |
| `categories` | `name` | `app/graphql/resolvers/categories_resolver.rb` |
| lookups (tolerances, growth habits, antinutrients, image attributes) | `name` | one resolver each |

The admin interface therefore offers a direction toggle on exactly one column
per list and leaves the rest as plain headers, because a client-side sort would
only reorder the 25 rows on screen and quietly misrepresent the other pages.

This is a scope note, not a plan of record. Nothing here is committed to.

## What clients would need

Per entity, the columns an admin actually wants to order by:

- **Plants** — primary common name, scientific name, family names, visibility, owner, updated at.
- **Specimens** — name, plant, created at, updated at, visibility, owner.
- **Locations** — name, soil quality, visibility, owner, updated at.
- **Categories and lookups** — name, updated at.

## The hard part: translated names

Sorting is not uniformly a column sort, and this is what decides the shape of
the work:

- `Plant#scientific_name`, `Location#name` and `Specimen#name` are **plain
  columns** and sort trivially.
- `Category#name` and every lookup `name` are **Mobility `:container` fields**
  living in a jsonb `translations` column. Ordering them means ordering on
  `translations -> :<locale> ->> 'name'`, which is locale-dependent, does not
  use an ordinary index, and has to decide what happens to records with no
  translation in the requested locale.
- **Plant primary common name** is worse: it resolves through the
  `common_names` association with a per-locale primary flag, so ordering means a
  correlated subquery or a denormalised column.

A first pass could offer only the plain-column keys and say so, rather than
shipping a sort that silently disagrees with what the column displays.

## Scale first, because it changes the answer

Production, 2026-08-02: **322 plants, 707 varieties, 13 categories, 7 tolerances, 5 growth habits, 19 antinutrients.** Specimens and locations are mostly private, so the anonymous counts understate them, but nothing here is large.

There is **no index on `scientific_name`, `family_names`, `name` or `created_at`** on any of these tables (`db/structure.sql` indexes only `visibility`, `owned_by`, `owner_organization_id`, the partial `deleted_at`, and the sync uniqueness pairs). Today's default sort is already a sequential scan plus an in-memory sort, and nobody has noticed, because sorting a few hundred rows costs microseconds.

So for every candidate below, **performance is not the constraint.** Do not add indexes speculatively. The cost is in semantics: what the ordering *means* when the value is missing, duplicated, or locale-dependent.

## Candidate keys, by value and by lift

Measured against the 322 production plants and their 1,566 common names.

### Worth doing, cheap

| Key | Why someone wants it | Lift |
| --- | --- | --- |
| **`scientific_name`** (plants) | Already the default. It is present on **all 322 plants** (0 null), and it is the identifier the data is increasingly keyed on. | Done. Needs only the tiebreaker below. |
| **`updated_at`** (every entity) | "What changed recently?" This is the single most useful missing sort in a curation tool, and the only one that answers a question the filters cannot. It is also how you find work in progress after a bulk import or a sync run. | Trivial. Plain indexed-able column, already exposed as `updatedAt`. |
| **`created_at`** (every entity) | "What is new?" Already the specimens default. | Trivial, same shape. |
| **`family_names`** (plants) | Browsing by botanical family: 85 distinct values across 300 populated rows, 22 blank. Good grouping cardinality, and a sort is the poor-man's grouping. | Trivial, plain column. Consider whether it should be a *filter* instead. |

### Worth doing, but sort is the wrong tool

| Key | Why it looks appealing | Why not |
| --- | --- | --- |
| **`visibility`** | "Show me the drafts." | Four values across hundreds of rows. Sorting clusters them but still makes you scroll; the list already has a visibility **filter**, which answers the question exactly. Adding a sort here spends schema surface to do a worse job. |
| **owner** | "Show me one org's records." | Same argument. `owned_by` is a plain indexed column, but the list already filters by owner and by organization. Worse, the column now *displays* `ownerOrganization.name`, so sorting by `owned_by` would order by a value the user cannot see. If this is wanted, it is a sort on the joined organization name, which is a join plus a nullable fallback to the email. |

### Expensive, and the reason to be careful: `primary_common_name`

This is the one that looks like a column and is not. `Plant#primary_common_name` (`app/models/plant.rb:146`) resolves **four tiers per row, per locale**:

1. the `primary` common name in the requested locale, else
2. the `primary` common name in `EN`, else
3. the first `EN` common name by id, else
4. `nil`

What the production data says about how often each tier is reached:

- 1,566 common names across **30 language codes**, up to **32 per plant**.
- `primary` flags exist in only 5 languages: EN 265, ES 51, FR 37, HT 8, TH 1.
- **58 of 322 plants (18%) have no EN primary** — they resolve past tier 2.
- **51 of 322 plants (16%) have no `primary` flag in any language** — they land on tier 3, "first EN row by id", i.e. *insertion order decides the displayed name*.
- **20 plants (6%) show no common name at all** (tier 4).
- 4 plants have no common names whatsoever.

To sort on this in SQL you must reproduce that precedence in one orderable expression — a correlated subquery or `LATERAL` per row, parameterised by locale, with `NULLS LAST`. It is writable, but three things follow that make it a poor first move:

1. **It is locale-dependent.** The same list sorts differently per `Accept-Language`, so a shared link does not reproduce the order the sender saw unless the locale is part of the link.
2. **For a third of the catalogue the sort key is arbitrary.** Ordering by a value that tier 3 picked by insertion order is ordering by noise, and it will look like a bug.
3. **It cannot use an index** in any straightforward form, and the ordering expression has to stay byte-identical to `primary_common_name_from_loaded` or the list will sort by one name and display another.

**Recommendation: do not sort on primary common name.** Search already covers the real need — `anyName` matches scientific *and* common names, so typing "okra" finds the plant regardless of which name you know. If a common-name sort is still wanted after that, the honest prerequisite is a denormalised, locale-resolved column maintained on write, not a query-time expression.

The same argument applies, more weakly, to `Category#name` and the lookup `name` fields, which are Mobility `:container` jsonb: orderable via `translations -> :<locale> ->> 'name'`, locale-dependent, unindexed. At 13 categories and 5-19 lookup rows, a sort control there is not worth any lift at all.

### Data-quality findings, surfaced by this analysis

Worth fixing regardless of sorting, because they already affect what the app displays today:

- **`language` codes are not normalised.** 846 rows use `EN` and **1 uses lowercase `en`**. The resolver matches `where(language: locale.upcase)`, so that row can never satisfy tier 1 or 2 and is effectively invisible to primary-name resolution.
- **`JP` is used once where `JA` (19 rows) is the ISO code** for Japanese, so those names are split across two codes.
- **51 plants have no `primary` flag on any common name**, which means the displayed name is whichever row was inserted first. If common names matter for display, these want a curation pass.

## The tiebreaker is not optional

13 scientific names are duplicated across the 322 plants (`Amaranthus caudatus`, `Cucurbita moschata`, ...), and 3 common names repeat. Cursor pagination over a non-unique ordering can **skip or repeat rows between pages** — the bug exists in the current default sort today, it is simply rare enough at 25 rows per page not to have been noticed. Any `order` clause added here, and the existing ones, must append `id` as a final tiebreaker.

## Suggested first slice

1. Append the `id` tiebreaker to the existing sorts. Bug fix, no API change.
2. Add `sortBy` with `UPDATED_AT` and `CREATED_AT` for every entity, plus `SCIENTIFIC_NAME` and `FAMILY_NAMES` for plants and `NAME` where it is a plain column. All plain columns, all locale-independent.
3. Stop there. Revisit common-name sorting only if someone asks for it after using recency sorting for a while.

## Suggested shape

Keep `sortDirection` exactly as it is -- it is part of the frozen mobile
contract (`spec/contracts/mobile_*`) -- and add an optional companion:

```graphql
plants(sortBy: PlantSortField = SCIENTIFIC_NAME, sortDirection: SortDirection = ASC)
```

A per-entity enum rather than a shared one, so the schema states which fields an
entity can actually order by and an invalid combination is a schema error rather
than a runtime surprise. `search_object` already dispatches
`apply_sort_direction_with_asc/desc`; a `sortBy` option would replace those two
methods with a single `apply_sort` that maps enum value plus direction to an
`order` clause.

Points to settle before writing code:

1. **Stable tiebreaker.** Cursor pagination over a non-unique sort key can skip
   or repeat rows between pages. Every order clause needs a deterministic
   tiebreaker (`id`) appended.
2. **Indexes.** Check `db/structure.sql` for each proposed key; sorting a large
   table on an unindexed column is a sequential scan plus a sort on every page.
3. **Locale.** If translated keys are in scope, the order clause depends on
   `Mobility.locale`, which the resolver sets from the `language` argument or
   the `Accept-Language` header. Decide where untranslated records land.
4. **Default.** The default must stay each list's current key, or the mobile
   client's paging changes under it.
5. **Contract specs.** `spec/contracts/mobile_*` must keep passing untouched;
   the new argument is additive and the frozen documents never send it.

## Client side

The admin interface is ready for this: `DataTable`'s `sort` prop already carries
`{ columnKey, direction, label, onToggle }` and `useListState` already keeps the
direction in the URL (`?dir=`). Making more columns sortable means widening that
prop to a per-column key and adding `?sortBy=` beside it. See
`plant_data_admin_interface/docs/conventions.md`, "Shared components → DataTable".
