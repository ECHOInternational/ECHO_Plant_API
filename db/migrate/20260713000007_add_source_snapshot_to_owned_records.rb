# frozen_string_literal: true

# Adds source_snapshot jsonb to the five independently-owned tables.
# This column stores the last accepted source-managed attribute values (the
# three-way BASE used by SourceSynchronizer for conflict detection).
# All additions are nullable so existing rows are unaffected until a sync runs.
class AddSourceSnapshotToOwnedRecords < ActiveRecord::Migration[8.1]
  OWNED_TABLES = %i[plants varieties specimens locations categories].freeze

  def up
    OWNED_TABLES.each do |table|
      add_column table, :source_snapshot, :jsonb
    end
  end

  def down
    OWNED_TABLES.each do |table|
      remove_column table, :source_snapshot
    end
  end
end
