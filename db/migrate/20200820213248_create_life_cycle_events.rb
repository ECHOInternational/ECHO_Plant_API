class CreateLifeCycleEvents < ActiveRecord::Migration[6.0]
  def up
    execute <<-SQL
      CREATE TYPE unit AS ENUM ('weight', 'count');
      CREATE TYPE soil_preparation AS ENUM ('greenhouse', 'planting_station', 'no_till', 'full_till', 'raised_beds', 'vertical_garden', 'container', 'other');
    SQL
    create_table :life_cycle_events, id: :uuid do |t|
      t.string :type, null: false
      t.references :specimen, null: false, foreign_key: true, type: :uuid
      t.references :location, null: true, foreign_key: true, type: :uuid
      t.datetime :datetime, null: false
      t.text :notes
      t.float :quantity
      t.integer :quality
      t.integer :percent
      t.string :source
      t.string :accession
      t.column :condition, :condition
      t.column :unit, :unit
      t.integer :between_row_spacing
      t.integer :in_row_spacing
      t.column :soil_preparation, :soil_preparation

      t.timestamps
    end
  end

  def down
    drop_table :life_cycle_events
    execute <<-SQL
      DROP TYPE unit;
      DROP TYPE soil_preparation;
    SQL
  end
end
