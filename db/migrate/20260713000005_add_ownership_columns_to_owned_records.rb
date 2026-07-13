# frozen_string_literal: true

# Adds the Phase A ownership/source/sync/publication columns to the five
# independently-owned tables. All new columns are nullable so existing rows are
# unaffected until the Phase B backfill runs. Indexes are additive only.
class AddOwnershipColumnsToOwnedRecords < ActiveRecord::Migration[8.1]
  OWNED_TABLES = %i[plants varieties specimens locations categories].freeze

  def up
    OWNED_TABLES.each do |table|
      add_column table, :owner_organization_id, :uuid
      add_column table, :source_organization_id, :uuid
      add_column table, :created_by_principal_id, :uuid
      add_column table, :data_source_id, :uuid
      add_column table, :source_record_id, :string
      add_column table, :source_updated_at, :timestamptz
      add_column table, :last_synced_at, :timestamptz
      add_column table, :source_digest, :string
      add_column table, :sync_state, :string
      add_column table, :publication_state, :string
      add_column table, :access_level, :string
      add_column table, :deleted_at, :timestamptz
      add_column table, :deleted_by_principal_id, :uuid

      # FK indexes (non-unique)
      add_index table, :owner_organization_id,
                name: "index_#{table}_on_owner_organization_id"

      # Unique partial: (data_source_id, source_record_id) per-source uniqueness
      add_index table, %i[data_source_id source_record_id],
                unique: true,
                where: 'data_source_id IS NOT NULL',
                name: "index_#{table}_on_data_source_and_source_record"

      # Partial index on deleted_at for soft-delete queries
      add_index table, :deleted_at,
                where: 'deleted_at IS NOT NULL',
                name: "index_#{table}_on_deleted_at_partial"

      # Plain btree indexes on existing legacy columns (currently unindexed)
      add_index table, :visibility,
                name: "index_#{table}_on_visibility"
      add_index table, :owned_by,
                name: "index_#{table}_on_owned_by"
    end

    # Also index images.visibility and images.owned_by (legacy scopes, unindexed)
    add_index :images, :visibility,  name: 'index_images_on_visibility'
    add_index :images, :owned_by,    name: 'index_images_on_owned_by'

    # FK constraints (deferred to separate alter statements for clarity)
    OWNED_TABLES.each do |table|
      add_foreign_key table, :organizations,
                      column: :owner_organization_id,
                      name: "fk_#{table}_owner_org"
      add_foreign_key table, :organizations,
                      column: :source_organization_id,
                      name: "fk_#{table}_source_org"
      add_foreign_key table, :principals,
                      column: :created_by_principal_id,
                      name: "fk_#{table}_created_by_principal"
      add_foreign_key table, :data_sources,
                      column: :data_source_id,
                      name: "fk_#{table}_data_source"
      add_foreign_key table, :principals,
                      column: :deleted_by_principal_id,
                      name: "fk_#{table}_deleted_by_principal"
    end
  end

  def down
    OWNED_TABLES.each do |table|
      # Remove FKs first
      remove_foreign_key table, name: "fk_#{table}_owner_org"
      remove_foreign_key table, name: "fk_#{table}_source_org"
      remove_foreign_key table, name: "fk_#{table}_created_by_principal"
      remove_foreign_key table, name: "fk_#{table}_data_source"
      remove_foreign_key table, name: "fk_#{table}_deleted_by_principal"

      # Remove indexes
      remove_index table, name: "index_#{table}_on_owner_organization_id"
      remove_index table, name: "index_#{table}_on_data_source_and_source_record"
      remove_index table, name: "index_#{table}_on_deleted_at_partial"
      remove_index table, name: "index_#{table}_on_visibility"
      remove_index table, name: "index_#{table}_on_owned_by"

      # Remove columns
      remove_column table, :owner_organization_id
      remove_column table, :source_organization_id
      remove_column table, :created_by_principal_id
      remove_column table, :data_source_id
      remove_column table, :source_record_id
      remove_column table, :source_updated_at
      remove_column table, :last_synced_at
      remove_column table, :source_digest
      remove_column table, :sync_state
      remove_column table, :publication_state
      remove_column table, :access_level
      remove_column table, :deleted_at
      remove_column table, :deleted_by_principal_id
    end

    remove_index :images, name: 'index_images_on_visibility'
    remove_index :images, name: 'index_images_on_owned_by'
  end
end
