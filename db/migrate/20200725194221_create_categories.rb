class CreateCategories < ActiveRecord::Migration[6.0]
  def change
    create_table :categories, id: :uuid do |t|
      t.jsonb :translations, default: {}, null: false
      t.string :created_by, null: false
      t.string :owned_by, null: false
      t.integer :visibility, null: false, default: 0
      
      t.timestamps
    end
  end
end
