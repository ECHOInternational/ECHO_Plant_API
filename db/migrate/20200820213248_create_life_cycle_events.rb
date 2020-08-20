class CreateLifeCycleEvents < ActiveRecord::Migration[6.0]
  def up
    execute <<-SQL
      CREATE TYPE condition AS ENUM ('poor', 'fair', 'good');
    SQL
    create_table :life_cycle_events, id: :uuid do |t|
      t.string :type, null: false
      t.references :specimen, null: false, foreign_key: true, type: :uuid
      t.references :location, null: true, foreign_key: true, type: :uuid
      t.datetime :datetime, null: false
      t.text :notes
      t.float :quantity
      t.string :unit
      t.integer :quality
      t.string :source
      t.string :accession
      t.column :condition, :condition

      t.timestamps
    end
  end

  def down
    drop_table :life_cycle_events
    execute <<-SQL
      DROP TYPE condition;
    SQL
  end
end
