class CreateVarieties < ActiveRecord::Migration[6.0] # rubocop:disable
  def change
    create_table :varieties, id: :uuid do |t|
      t.references :plant, null: false, foreign_key: true, type: :uuid
      t.jsonb :translations, default: {}, null: false
      t.string :created_by, null: false
      t.string :owned_by, null: false
      t.integer :visibility, null: false, default: 0
      t.int4range :n_accumulation_range, default: (0..0)
      t.numrange :biomass_production_range, default: (0..0)
      t.int4range :optimal_temperature_range, default: (0..60)
      t.int4range :optimal_rainfall_range, default: (0..)
      t.int4range :seasonality_days_range
      t.int4range :optimal_altitude_range, default: (0..)
      t.numrange :ph_range, default: (0.0..14.0)
      t.boolean :has_edible_green_leaves
      t.boolean :has_edible_immature_fruit
      t.boolean :has_edible_mature_fruit
      t.boolean :can_be_used_for_fodder
      t.column :early_growth_phase, :early_growth_phase
      t.column :life_cycle, :life_cycle

      t.timestamps
    end

    create_table :tolerances_varieties, id: :uuid do |t|
      t.references :tolerance, null: false, foreign_key: true, type: :uuid
      t.references :variety, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :tolerances_varieties, %i[tolerance_id variety_id], unique: true

    create_table :growth_habits_varieties, id: :uuid do |t|
      t.references :growth_habit, null: false, foreign_key: true, type: :uuid
      t.references :variety, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :growth_habits_varieties, %i[growth_habit_id variety_id], unique: true

    create_table :antinutrients_varieties, id: :uuid do |t|
      t.references :antinutrient, null: false, foreign_key: true, type: :uuid
      t.references :variety, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :antinutrients_varieties, %i[antinutrient_id variety_id], unique: true
  end
end
