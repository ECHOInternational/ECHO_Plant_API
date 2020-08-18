class CreateTolerances < ActiveRecord::Migration[6.0]
  def change
    create_table :tolerances, id: :uuid do |t|
      t.jsonb :translations, default: {}, null: false

      t.timestamps
    end
  end
end
