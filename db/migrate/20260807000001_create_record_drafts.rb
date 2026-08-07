# frozen_string_literal: true

class CreateRecordDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :record_drafts, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :draftable_type, null: false
      t.uuid   :draftable_id,   null: false

      # Changed keys only, using model attribute names. `translations` is one
      # key holding the whole Mobility container blob.
      t.jsonb :data, null: false, default: {}

      # The live row's updated_at when this draft was CREATED. Never advanced by
      # subsequent draft saves: if it were, a conflict arriving mid-draft would
      # be silently swallowed.
      t.datetime :base_updated_at, null: false

      t.uuid :author_principal_id,      null: false
      t.uuid :last_editor_principal_id, null: false

      t.timestamps
    end

    # One draft per record, enforced by the database rather than by convention.
    add_index :record_drafts, %i[draftable_type draftable_id], unique: true,
                                                               name: 'index_record_drafts_on_draftable'
    add_foreign_key :record_drafts, :principals, column: :author_principal_id
    add_foreign_key :record_drafts, :principals, column: :last_editor_principal_id
  end
end
