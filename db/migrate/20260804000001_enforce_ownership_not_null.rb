# frozen_string_literal: true

# S7: the ownership columns become mandatory.
#
# Every owned record has carried an owner organization, a source organization
# and a creating principal since the S3 backfill, and `rake ownership:verify`
# reported PASS against production immediately before this shipped. The columns
# were left nullable only so the backfill could run against live traffic.
#
# Why not a plain `change_column_null`: on Postgres that takes ACCESS EXCLUSIVE
# and scans the whole table while holding it, which stalls every reader and
# writer on a live service. The three-step form below does the scan under a
# weaker lock:
#
#   1. ADD CONSTRAINT ... CHECK (col IS NOT NULL) NOT VALID   -- instant
#   2. VALIDATE CONSTRAINT                                    -- scans, no
#                                                                exclusive lock
#   3. SET NOT NULL                                           -- PG12+ sees the
#                                                                validated CHECK
#                                                                and skips its
#                                                                own scan
#
# The CHECK is then redundant and is dropped.
class EnforceOwnershipNotNull < ActiveRecord::Migration[8.1]
  TABLES = %i[plants varieties specimens locations categories].freeze
  COLUMNS = %i[owner_organization_id source_organization_id created_by_principal_id].freeze

  disable_ddl_transaction!

  def up
    TABLES.each do |table|
      COLUMNS.each do |column|
        constraint = "#{table}_#{column}_not_null"

        execute <<~SQL.squish
          ALTER TABLE #{table}
          ADD CONSTRAINT #{constraint} CHECK (#{column} IS NOT NULL) NOT VALID
        SQL
        execute "ALTER TABLE #{table} VALIDATE CONSTRAINT #{constraint}"
        change_column_null table, column, false
        execute "ALTER TABLE #{table} DROP CONSTRAINT #{constraint}"
      end
    end
  end

  def down
    TABLES.each do |table|
      COLUMNS.each { |column| change_column_null table, column, true }
    end
  end
end
