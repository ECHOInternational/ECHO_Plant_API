# frozen_string_literal: true

# The plant-to-climate-zone join (D-017), matching categories_plants.
#
# ECHOcommunity holds 512 of these. Its own join table has no foreign keys and
# no unique index, which is how it came to contain one row pointing at a zone
# that does not exist; both constraints are present here.
class CreateKoppenZonesPlants < ActiveRecord::Migration[8.1]
  def change
    create_table :koppen_zones_plants, id: :uuid do |t|
      t.references :koppen_zone, null: false, foreign_key: true, type: :uuid
      t.references :plant, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :koppen_zones_plants, %i[koppen_zone_id plant_id], unique: true
  end
end
