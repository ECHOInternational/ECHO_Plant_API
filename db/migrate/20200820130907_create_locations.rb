class CreateLocations < ActiveRecord::Migration[6.0]
  def change
    create_table :locations, id: :uuid do |t|
      t.string :name, null: false
      t.string :created_by, null: false
      t.string :owned_by, null: false
      t.integer :visibility, null: false, default: 0
      t.point :latlng
      t.float :area
      t.integer :soil_quality, null: false, default: 1
      t.integer :slope
      t.integer :altitude
      t.integer :average_rainfall
      t.integer :average_temperature
      t.boolean :irrigated
      t.text :notes

      t.timestamps
    end
  end
end
