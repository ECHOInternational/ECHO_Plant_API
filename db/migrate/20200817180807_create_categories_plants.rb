class CreateCategoriesPlants < ActiveRecord::Migration[6.0]
  def change
    create_table :categories_plants, id: :uuid do |t|
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.references :plant, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :categories_plants, %i[category_id plant_id], unique: true
  end
end
