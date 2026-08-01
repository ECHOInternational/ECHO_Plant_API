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
