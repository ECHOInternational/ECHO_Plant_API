# frozen_string_literal: true

require Rails.root.join('lib/image_positions')

# Display order for images (FPI plan API-5, decision Q5): images.position,
# 1-based within one imageable, plus the (imageable_type, imageable_id,
# position) index the ordered images connections read through. There was no
# index on the imageable columns at all before this.
#
# Production-safe:
#   * the column is nullable with no default, so adding it is a catalog-only
#     change; lock_timeout bounds the brief ACCESS EXCLUSIVE lock it needs;
#   * the index is built CONCURRENTLY (hence no DDL transaction);
#   * the backfill (lib/image_positions.rb) is raw SQL in short per-batch
#     transactions of 500 parents: no versions, updated_at untouched.
#
# The column stays nullable: an image inserted by the previous release while
# this one rolls out has no position, and the display order sorts NULLs last
# (where an appended image belongs anyway). New code always assigns one.
class AddPositionToImages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = 'index_images_on_imageable_and_position'

  def up
    with_lock_timeout { add_column :images, :position, :integer, if_not_exists: true }
    add_index :images, %i[imageable_type imageable_id position],
              name: INDEX_NAME, algorithm: :concurrently, if_not_exists: true
    positioned = ImagePositions.backfill!(connection: connection)
    say "positioned #{positioned} images"
  end

  def down
    remove_index :images, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
    with_lock_timeout { remove_column :images, :position, if_exists: true }
  end

  private

  def with_lock_timeout
    execute "SET lock_timeout = '10s'"
    yield
  ensure
    execute 'RESET lock_timeout'
  end
end
