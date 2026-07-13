# frozen_string_literal: true

class CreateDataSources < ActiveRecord::Migration[8.1]
  def change
    create_table :data_sources, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.string :source_system_key, null: false
      t.text :notes
      t.timestamps
    end

    add_index :data_sources, :source_system_key, unique: true,
              name: "index_data_sources_on_source_system_key"
  end
end
