# frozen_string_literal: true

# Aggregated record history looks child versions up with
# `versions.metadata @> '{"root_type":"Plant","root_id":"<uuid>"}'`.
#
# GIN with jsonb_path_ops is the operator class for @> containment: smaller and
# faster than the default jsonb_ops, at the cost of key-existence operators we
# do not use. CONCURRENTLY keeps the build off an ACCESS EXCLUSIVE lock on a
# table every write in the application appends to; it cannot run inside a
# transaction, hence disable_ddl_transaction!.
class AddGinIndexToVersionsMetadata < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :versions,
              :metadata,
              using: :gin,
              opclass: :jsonb_path_ops,
              algorithm: :concurrently,
              name: 'index_versions_on_metadata_jsonb_path_ops',
              if_not_exists: true
  end
end
