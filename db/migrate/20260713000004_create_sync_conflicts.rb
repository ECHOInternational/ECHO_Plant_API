# frozen_string_literal: true

class CreateSyncConflicts < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_conflicts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :syncable_type, null: false
      t.uuid    :syncable_id,   null: false
      t.references :data_source, type: :uuid, null: false, foreign_key: true
      t.string  :conflict_type, null: false
      t.jsonb   :base_payload
      t.jsonb   :local_payload
      t.jsonb   :incoming_payload
      t.string  :status, null: false, default: "open"
      t.string  :resolution
      t.references :resolved_by_principal, type: :uuid, foreign_key: { to_table: :principals }
      t.timestamptz :resolved_at
      t.string  :sync_run_id
      t.jsonb   :metadata, default: {}
      t.timestamps
    end

    add_index :sync_conflicts, %i[syncable_type syncable_id],
              name: "index_sync_conflicts_on_syncable"
    add_index :sync_conflicts, %i[data_source_id status],
              name: "index_sync_conflicts_on_data_source_and_status"
  end
end
