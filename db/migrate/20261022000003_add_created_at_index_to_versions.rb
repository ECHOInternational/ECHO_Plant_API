# frozen_string_literal: true

# plants(updatedSince:) (FPI plan API-9) finds plants whose children changed
# through versions.created_at (common names, relation links and images stamp
# their root plant into versions.metadata). versions had no created_at index
# (250,688 rows, 436 MB on the 2026-10-22 production copy), so the index is
# built CONCURRENTLY: no write lock on versions while it builds.
class AddCreatedAtIndexToVersions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :versions, :created_at, algorithm: :concurrently, if_not_exists: true
  end
end
