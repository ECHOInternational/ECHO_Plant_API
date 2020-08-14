# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2020_08_14_173300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension 'pgcrypto'
  enable_extension 'plpgsql'

  create_table 'antinutrients', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.jsonb 'translations', default: {}, null: false
    t.datetime 'created_at', precision: 6, null: false
    t.datetime 'updated_at', precision: 6, null: false
  end

  create_table 'categories', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.jsonb 'translations', default: {}, null: false
    t.string 'created_by', null: false
    t.string 'owned_by', null: false
    t.integer 'visibility', default: 0, null: false
    t.datetime 'created_at', precision: 6, null: false
    t.datetime 'updated_at', precision: 6, null: false
  end

  create_table 'image_attributes', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.jsonb 'translations', default: {}, null: false
    t.datetime 'created_at', precision: 6, null: false
    t.datetime 'updated_at', precision: 6, null: false
  end

  create_table 'image_attributes_images', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'image_attribute_id', null: false
    t.uuid 'image_id', null: false
    t.datetime 'created_at', precision: 6, null: false
    t.datetime 'updated_at', precision: 6, null: false
    t.index ['image_attribute_id'], name: 'index_image_attributes_images_on_image_attribute_id'
    t.index ['image_id', 'image_attribute_id'], name: 'index_image_attributes_image_on_both_ids', unique: true
    t.index ['image_id'], name: 'index_image_attributes_images_on_image_id'
  end

  create_table 'images', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.jsonb 'translations', default: {}, null: false
    t.string 'attribution'
    t.string 's3_bucket', null: false
    t.string 's3_key', null: false
    t.string 'created_by', null: false
    t.string 'owned_by', null: false
    t.integer 'visibility', default: 0, null: false
    t.string 'imageable_type', null: false
    t.uuid 'imageable_id', null: false
    t.datetime 'created_at', precision: 6, null: false
    t.datetime 'updated_at', precision: 6, null: false
    t.index ['imageable_type', 'imageable_id'], name: 'index_images_on_imageable_type_and_imageable_id'
  end

  create_table 'versions', force: :cascade do |t|
    t.string 'item_type', null: false
    t.bigint 'item_id', null: false
    t.string 'event', null: false
    t.string 'whodunnit'
    t.text 'object'
    t.datetime 'created_at'
    t.text 'object_changes'
    t.index ['item_type', 'item_id'], name: 'index_versions_on_item_type_and_item_id'
  end

  add_foreign_key 'image_attributes_images', 'image_attributes'
  add_foreign_key 'image_attributes_images', 'images'
end
