class CreateSpecimens < ActiveRecord::Migration[6.0]
  def change
    create_table :specimens, id: :uuid do |t|
      t.string :name, null: false
      t.references :plant, null: false, foreign_key: true, type: :uuid
      t.references :variety, null: true, foreign_key: true, type: :uuid
      t.boolean :terminated, null: false, default: false
      t.string :created_by, null: false
      t.string :owned_by, null: false
      t.integer :visibility, null: false, default: 0

      t.timestamps
    end
  end
end
