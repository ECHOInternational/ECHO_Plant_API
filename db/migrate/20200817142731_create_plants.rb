class CreatePlants < ActiveRecord::Migration[6.0] # rubocop:disable
  def up
    execute <<-SQL
      CREATE TYPE early_growth_phase AS ENUM ('slow', 'intermediate', 'fast');
      CREATE TYPE life_cycle AS ENUM ('annual', 'biennial', 'perennial');
    SQL
    create_table :plants, id: :uuid do |t|
      t.jsonb :translations, default: {}, null: false
      t.string :created_by, null: false
      t.string :owned_by, null: false
      t.integer :visibility, null: false, default: 0
      t.string :scientific_name
      t.string :family_names
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
  end

  def down
    drop_table :plants
    execute <<-SQL
      DROP TYPE early_growth_phase;
      DROP TYPE life_cycle;
    SQL
  end
end
