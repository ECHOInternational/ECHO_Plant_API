class CreateAntinutrientsPlants < ActiveRecord::Migration[6.0]
  def change
    create_table :antinutrients_plants, id: :uuid do |t|
      t.references :antinutrient, null: false, foreign_key: true, type: :uuid
      t.references :plant, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :antinutrients_plants, %i[antinutrient_id plant_id], unique: true
  end
end
