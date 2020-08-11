# frozen_string_literal: true

class CreateImageAttributesImages < ActiveRecord::Migration[6.0]
  def change
    create_table :image_attributes_images, id: :uuid do |t|
      t.references :image_attribute, null: false, foreign_key: true, type: :uuid
      t.references :image, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :image_attributes_images, [:image_id, :image_attribute_id], unique: true, name: 'index_image_attributes_image_on_both_ids'
  end
end
