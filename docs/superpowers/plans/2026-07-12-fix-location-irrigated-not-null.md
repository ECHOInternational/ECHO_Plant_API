# Fix Location.irrigated NOT NULL Production Bug

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backfill and constrain `locations.irrigated` to NOT NULL/default false so the GraphQL `irrigated: Boolean!` field never returns null and the production crash is eliminated.

**Architecture:** Single migration: backfill 7 NULL rows → add DEFAULT false → add NOT NULL. Update db/structure.sql with only the legitimate hunk (one-line irrigated column change). New spec file proves the DB-level constraint and the GraphQL resolver both work. The GraphQL SDL is NOT touched.

**Tech Stack:** Rails 8.1.3 / Ruby 3.4.10, PostgreSQL (Docker Compose), RSpec, graphql-ruby.

## Global Constraints

- Branch: `fix-location-irrigated-not-null` (from up-to-date master).
- Do NOT push or merge.
- Do NOT touch `app/graphql/types/location_type.rb` or `schema.graphql`.
- Do NOT touch tripwire specs: `spec/contracts/`, `spec/models/*_compat_spec.rb`, `paper_trail_item_id_spec`, `policy_scope_loaded_drift_spec`.
- `db/structure.sql` must be hand-curated: commit only the real irrigated-column hunk + the schema_migrations row; exclude pg_dump cosmetic churn.
- Test env forced per command: `docker compose run -e RAILS_ENV=test web bundle exec rspec`.
- The `bench-pg16` container (postgres:16, database `benchmark_prod`) is READ-ONLY: use BEGIN/ROLLBACK; never permanently mutate it.
- Full suite must remain ~1300+/0 (no failures, no regressions).

---

### Task 1: Branch + migration

**Files:**
- Modify: `db/migrate/20260712000000_make_locations_irrigated_not_null.rb` (create new)
- Modify: `db/structure.sql` (one-line change to irrigated column + schema_migrations INSERT)

**Interfaces:**
- Produces: a runnable migration that sets DEFAULT false NOT NULL on `locations.irrigated`

- [ ] **Step 1: Create the branch**

```bash
git checkout -b fix-location-irrigated-not-null
```

Expected: switched to new branch `fix-location-irrigated-not-null`

- [ ] **Step 2: Verify prod snapshot before backfill (READ-ONLY)**

```bash
docker exec bench-pg16 psql -U postgres -d benchmark_prod -c \
  "SELECT count(*) FILTER (WHERE irrigated IS NULL) FROM locations;"
```

Expected: count = 7

- [ ] **Step 3: Verify the UPDATE hits exactly 7 rows (BEGIN/ROLLBACK — never commits)**

```bash
docker exec bench-pg16 psql -U postgres -d benchmark_prod -c \
  "BEGIN; UPDATE locations SET irrigated = false WHERE irrigated IS NULL; SELECT count(*) FILTER (WHERE irrigated IS NULL) FROM locations; ROLLBACK;"
```

Expected: UPDATE 7, then count = 0, then ROLLBACK.

- [ ] **Step 4: Write the migration**

Create `/work/plant_data_upgrade/ECHO_Plant_API/db/migrate/20260712000000_make_locations_irrigated_not_null.rb`:

```ruby
# frozen_string_literal: true

# Production fix: 7 locations rows have NULL irrigated (legacy 2020 test data,
# owned by larrytest@echonet.org). The GraphQL field is declared `irrigated: Boolean!`
# (null: false) so these rows produce "Cannot return null for non-nullable field
# Location.irrigated" when the Locations tab queries them.
#
# Fix: backfill NULLs to false (the safe default — unspecified = not irrigated),
# add a DEFAULT, then add the NOT NULL constraint. Order is mandatory: backfill
# BEFORE the constraint or Postgres will reject it on existing rows.
class MakeLocationsIrrigatedNotNull < ActiveRecord::Migration[8.1]
  def up
    # 1. Backfill any existing NULLs to false.
    execute "UPDATE locations SET irrigated = false WHERE irrigated IS NULL"

    # 2. Set the column default so future INSERTs without irrigated get false.
    change_column_default :locations, :irrigated, false

    # 3. Add the NOT NULL constraint (safe now that NULLs are gone).
    change_column_null :locations, :irrigated, false
  end

  def down
    change_column_null :locations, :irrigated, true
    change_column_default :locations, :irrigated, nil
  end
end
```

- [ ] **Step 5: Run the migration on the dev DB**

```bash
docker compose run web bundle exec rails db:migrate
```

Expected: output shows `MakeLocationsIrrigatedNotNull: migrated` with no errors.

- [ ] **Step 6: Verify migration status**

```bash
docker compose run web bundle exec rails db:migrate:status | grep irrigated
```

Expected: `up   20260712000000  Make locations irrigated not null`

- [ ] **Step 7: Regenerate structure.sql**

```bash
docker compose run web bundle exec rails db:schema:dump
```

Then inspect the diff. The only legitimate change to the locations table line is:

```
-    irrigated boolean,
+    irrigated boolean DEFAULT false NOT NULL,
```

And there should be a new schema_migrations row:
```
+('20260712000000');
```

- [ ] **Step 8: Hand-curate structure.sql**

Open `db/structure.sql`. Accept ONLY:
1. The `irrigated` column line change (DEFAULT false NOT NULL).
2. The new `('20260712000000')` line in the `schema_migrations` INSERT block.

If pg_dump added other cosmetic churn (SET statements, schema blocks, comment blocks, reordering), revert those lines to what was committed before (use `git diff db/structure.sql` and restore any non-irrigated changes).

- [ ] **Step 9: Confirm the curated diff**

```bash
git diff db/structure.sql
```

Expected: exactly two hunks — the irrigated column and the schema_migrations version row. No other changes.

- [ ] **Step 10: Commit the migration + curated structure.sql**

```bash
git add db/migrate/20260712000000_make_locations_irrigated_not_null.rb db/structure.sql
git commit -m "fix: backfill and constrain locations.irrigated to NOT NULL / default false

7 production rows had NULL irrigated (larrytest@echonet.org 2020 data),
causing 'Cannot return null for non-nullable field Location.irrigated' on
the admin Locations tab. The GraphQL field was always Boolean! — the data
was wrong, not the schema.

Migration order: backfill NULLs -> add DEFAULT false -> add NOT NULL.
Verified against bench-pg16 benchmark_prod snapshot: UPDATE hits exactly
7 rows, post-backfill NULL count = 0.

structure.sql: only the legitimate irrigated column hunk and the new
schema_migrations row are committed; pg_dump cosmetic churn excluded.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UqRr9uSixH1G6P2bhf5xUz"
```

---

### Task 2: Specs proving the fix

**Files:**
- Create: `spec/models/location_irrigated_spec.rb`

**Interfaces:**
- Consumes: `Location` model, `PlantApiSchema`, factories `:location`, `:user` with `:superadmin` trait
- Produces: 3 passing examples pinning the DB-level NOT NULL, the DEFAULT false, and the GraphQL resolver

- [ ] **Step 1: Run the full suite BEFORE writing specs (baseline)**

```bash
docker compose run -e RAILS_ENV=test web bundle exec rspec --format progress 2>&1 | tail -5
```

Expected: something like `1300+ examples, 0 failures`

- [ ] **Step 2: Write the spec file**

Create `/work/plant_data_upgrade/ECHO_Plant_API/spec/models/location_irrigated_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

# Regression spec for the production crash:
# "Cannot return null for non-nullable field Location.irrigated"
#
# Root cause: 7 legacy rows had NULL irrigated; the GraphQL field is Boolean!.
# Fix: migration backfills NULLs -> false, adds DEFAULT false, adds NOT NULL.
#
# These examples pin all three layers of the fix.
RSpec.describe 'Location.irrigated NOT NULL constraint', type: :model do
  # 1. DB-level NOT NULL: attempting to persist irrigated: nil should fail.
  it 'raises a DB-level NOT NULL violation when irrigated is set to nil explicitly' do
    location = build(:location, irrigated: nil)
    # AR lets the in-memory object past model validations (no presence validation),
    # but the DB constraint must reject it.
    expect { location.save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  # 2. Column DEFAULT: creating a location via the GraphQL createLocation mutation
  #    without specifying irrigated yields false (column default).
  it 'defaults irrigated to false when the mutation omits the irrigated argument' do
    current_user = build(:user, :superadmin)

    query = <<~GRAPHQL
      mutation($input: CreateLocationInput!) {
        createLocation(input: $input) {
          location { id irrigated }
          errors { field message code }
        }
      }
    GRAPHQL

    result = PlantApiSchema.execute(
      query,
      context: { current_user: current_user },
      variables: {
        input: {
          name: 'Default irrigated test',
          soilQuality: 'FAIR'
        }
      }
    )

    expect(result['errors']).to be_nil
    payload = result.dig('data', 'createLocation')
    expect(payload['errors']).to be_empty
    expect(payload['location']['irrigated']).to eq false
  end

  # 3. GraphQL resolver: querying irrigated returns a non-null Boolean (the crash is gone).
  it 'resolves irrigated as a non-null Boolean in a GraphQL location query' do
    location = create(:location, :public, irrigated: true)
    location_id = PlantApiSchema.id_from_object(location, Location, {})

    query = <<~GRAPHQL
      query($id: ID!) {
        location(id: $id) {
          id
          irrigated
        }
      }
    GRAPHQL

    result = PlantApiSchema.execute(query, variables: { id: location_id })

    expect(result['errors']).to be_nil
    expect(result.dig('data', 'location', 'irrigated')).to eq true
  end
end
```

- [ ] **Step 3: Run ONLY the new spec to verify all 3 pass**

```bash
docker compose run -e RAILS_ENV=test web bundle exec rspec spec/models/location_irrigated_spec.rb --format documentation
```

Expected:
```
Location.irrigated NOT NULL constraint
  raises a DB-level NOT NULL violation when irrigated is set to nil explicitly
  defaults irrigated to false when the mutation omits the irrigated argument
  resolves irrigated as a non-null Boolean in a GraphQL location query

3 examples, 0 failures
```

- [ ] **Step 4: Run the full suite to confirm no regressions**

```bash
docker compose run -e RAILS_ENV=test web bundle exec rspec --format progress 2>&1 | tail -5
```

Expected: 1303+ examples (3 more than baseline), 0 failures.

- [ ] **Step 5: Commit the spec**

```bash
git add spec/models/location_irrigated_spec.rb
git commit -m "test: pin NOT NULL / default / GraphQL resolver for Location.irrigated

Three examples in spec/models/location_irrigated_spec.rb:
1. DB-level NOT NULL violation when irrigated persisted as nil.
2. createLocation mutation without irrigated argument defaults to false.
3. GraphQL query on irrigated returns non-null Boolean (regression guard
   for the production crash).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UqRr9uSixH1G6P2bhf5xUz"
```

---

### Task 3: Gates verification and report

**Files:**
- Create: `.superpowers/sdd/step-p7-report.md`

**Interfaces:**
- Consumes: all outputs from Tasks 1 and 2

- [ ] **Step 1: Verify schema.graphql is byte-identical**

```bash
docker compose run web bundle exec rails graphql:schema:dump 2>/dev/null; git diff --exit-code schema.graphql && echo "SCHEMA GATE PASSED" || echo "SCHEMA GATE FAILED"
```

Expected: `SCHEMA GATE PASSED`

- [ ] **Step 2: Run Rubocop on the new files**

```bash
docker compose run web bundle exec rubocop db/migrate/20260712000000_make_locations_irrigated_not_null.rb spec/models/location_irrigated_spec.rb
```

Expected: no offenses.

- [ ] **Step 3: Final full suite run**

```bash
docker compose run -e RAILS_ENV=test web bundle exec rspec 2>&1 | tail -10
```

Expected: 0 failures.

- [ ] **Step 4: Write the report to `.superpowers/sdd/step-p7-report.md`**

Fill in actual SHAs, row counts, and test numbers from your runs.

- [ ] **Step 5: Final status message**

Report: STATUS=PASS, branch name, two commit SHAs, one-line test summary, any concerns.
