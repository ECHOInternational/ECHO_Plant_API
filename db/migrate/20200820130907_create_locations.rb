class CreateLocations < ActiveRecord::Migration[6.0]
  def up
    execute <<-SQL
      CREATE TYPE condition AS ENUM ('poor', 'fair', 'good');
    SQL
    create_table :locations, id: :uuid do |t|
      t.string :name, null: false
      t.string :created_by, null: false
      t.string :owned_by, null: false
      t.integer :visibility, null: false, default: 0
      t.point :latlng
      t.float :area
      t.column :soil_quality, :condition
      t.integer :slope
      t.integer :altitude
      t.integer :average_rainfall
      t.integer :average_temperature
      t.boolean :irrigated
      t.text :notes

      t.timestamps
    end
  end

  def down
    drop_table :locations
    execute <<-SQL
      DROP TYPE condition;
    SQL
  end
end
