class CreateImageAttributes < ActiveRecord::Migration[6.0]
  def change
    create_table :image_attributes, id: :uuid do |t|
      t.jsonb :translations

      t.timestamps
    end
  end
end
