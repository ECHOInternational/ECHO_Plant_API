class CreateCommonNames < ActiveRecord::Migration[6.0]
  def change
    create_table :common_names, id: :uuid do |t|
      t.string :name, null: false
      t.string :language, null: false
      t.string :location
      t.references :plant, null: false, foreign_key: true, type: :uuid
      t.boolean :primary, null: false, default: false

      t.timestamps
    end
  end
end
