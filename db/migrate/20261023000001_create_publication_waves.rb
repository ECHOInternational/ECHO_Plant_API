# frozen_string_literal: true

# The publication-wave ledger of the FPI plan (task API-11, section 5.1).
#
# publication_waves: one row per wave (fpi-w1, fpi-w2, ...). A uuid primary
# key like every other table, so the wave's own PaperTrail versions keep a
# meaningful item_id; the human handle is the unique key string.
#
# publication_wave_items: one row per plant or image a wave changed, with the
# exact visibility columns before (prior) and after (applied). The unpublisher
# restores prior only where the row still equals applied. The items are the
# ledger, so they are deliberately NOT versioned (see PublicationWaveItem):
# wave 1 alone is about 20k rows. item_id has no foreign key because the item
# is polymorphic and must survive an FpiRollback that deletes its row.
class CreatePublicationWaves < ActiveRecord::Migration[8.1]
  def change
    create_table :publication_waves, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :key, null: false
      t.references :data_source, type: :uuid, null: false, foreign_key: true
      t.string :selector, null: false
      t.jsonb :selector_params, null: false, default: {}
      t.jsonb :rule_snapshot
      t.string :selection_digest, null: false
      t.string :state, null: false
      t.jsonb :counts, null: false, default: {}
      t.text :notes
      t.datetime :published_at
      t.datetime :unpublished_at
      t.timestamps
    end
    add_index :publication_waves, :key, unique: true

    create_table :publication_wave_items, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.references :publication_wave, type: :uuid, null: false, foreign_key: true, index: false
      t.string :item_type, null: false
      t.uuid :item_id, null: false
      t.uuid :plant_id, null: false
      t.string :origin, null: false
      t.string :state, null: false
      t.jsonb :prior
      t.jsonb :applied
      t.timestamps
    end
    add_index :publication_wave_items, %i[publication_wave_id item_type item_id], unique: true,
                                                                                  name: 'index_publication_wave_items_unique_item'
    add_index :publication_wave_items, %i[item_type item_id]
    add_index :publication_wave_items, %i[publication_wave_id plant_id]
  end
end
