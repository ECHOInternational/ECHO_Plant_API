# frozen_string_literal: true

# Provenance for images that arrive from a data source (fpi-connector schema-delta
# item 14). Mirrors plants: the data source, the source's own identity for the
# row ('photos:<ROWID>' / 'drawings:<ROWID>'), and the SHA-256 of the bytes as
# delivered, so a re-import is idempotent and "which images came from FPI" is a
# plain SQL question. Hand-made images leave all three NULL.
class AddSourceProvenanceToImages < ActiveRecord::Migration[8.1]
  def change
    add_reference :images, :data_source, type: :uuid, null: true, foreign_key: true, index: false
    add_column :images, :source_record_id, :string
    add_column :images, :source_digest, :string
    add_index :images, %i[data_source_id source_record_id], unique: true,
                                                            where: 'data_source_id IS NOT NULL',
                                                            name: 'index_images_on_data_source_and_source_record'
  end
end
