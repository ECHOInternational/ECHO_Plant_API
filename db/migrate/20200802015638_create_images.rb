# frozen_string_literal: true

class CreateImages < ActiveRecord::Migration[6.0]
  def change
    create_table :images, id: :uuid do |t|
      t.jsonb :translations, default: {}, null: false
      t.string :attribution
      t.string :s3_bucket, null: false
      t.string :s3_key, null: false
      t.string :created_by, null: false
      t.string :owned_by, null: false
      t.integer :visibility, null: false, default: 0
      t.references :imageable, polymorphic: true, null: false, type: :uuid

      t.timestamps
    end
  end
end
