class CreateGrowthHabitsPlants < ActiveRecord::Migration[6.0]
  def change
    create_table :growth_habits_plants, id: :uuid do |t|
      t.references :growth_habit, null: false, foreign_key: true, type: :uuid
      t.references :plant, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :growth_habits_plants, %i[growth_habit_id plant_id], unique: true
  end
end
