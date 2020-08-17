class CreateTolerancesPlants < ActiveRecord::Migration[6.0]
  def change
    create_table :tolerances_plants, id: :uuid do |t|
      t.references :tolerance, null: false, foreign_key: true, type: :uuid
      t.references :plant, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :tolerances_plants, %i[tolerance_id plant_id], unique: true
  end
end
