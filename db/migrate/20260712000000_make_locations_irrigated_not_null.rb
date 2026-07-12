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
    execute 'UPDATE locations SET irrigated = false WHERE irrigated IS NULL'

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
