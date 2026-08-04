# frozen_string_literal: true

# Lets a spec build the pre-backfill rows that S7's NOT NULL constraints now
# forbid.
#
# OwnershipBackfill and `ownership:verify` exist to repair and audit rows with
# null ownership. S7 makes those rows impossible in the schema, which is the
# point -- but it also means the backfill's own specs can no longer construct
# their subject. Retiring the backfill was considered and rejected: it is not in
# S7's scope (rollout.md), and `ownership:verify` remains the standing invariant
# check that gets run against production before and after ownership work.
#
# So the specs opt out of the constraint instead of the schema going without it.
# Tag an example or group `:pre_backfill` and the three ownership columns become
# nullable for its duration. Postgres DDL is transactional and RSpec wraps every
# example in a transaction that rolls back, so the constraints come back on
# their own -- there is no path where a tagged example leaves the test schema
# relaxed for the next one.
module PreBackfill
  TABLES  = %i[plants varieties specimens locations categories].freeze
  COLUMNS = %i[owner_organization_id source_organization_id created_by_principal_id].freeze

  def self.relax!
    conn = ActiveRecord::Base.connection
    TABLES.each do |table|
      COLUMNS.each do |column|
        conn.execute("ALTER TABLE #{table} ALTER COLUMN #{column} DROP NOT NULL")
      end
    end
  end
end

RSpec.configure do |config|
  config.before(:each, :pre_backfill) { PreBackfill.relax! }
end
