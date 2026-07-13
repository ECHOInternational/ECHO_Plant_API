# frozen_string_literal: true

class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: 'personal'
      t.uuid :external_idp_id
      # index: false because we add a unique index below instead of the
      # default non-unique one that t.references would generate.
      t.references :principal, type: :uuid, foreign_key: true, index: false
      t.timestamps
    end

    add_index :organizations, :external_idp_id, unique: true,
                                                name: 'index_organizations_on_external_idp_id'
    add_index :organizations, :principal_id, unique: true,
                                             name: 'index_organizations_on_principal_id'

    # CHECK constraint enforcing kind shape
    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE organizations
            ADD CONSTRAINT organizations_kind_shape CHECK (
              (kind = 'real' AND external_idp_id IS NOT NULL AND principal_id IS NULL)
              OR (kind = 'personal' AND principal_id IS NOT NULL AND external_idp_id IS NULL)
            )
        SQL
      end
      dir.down do
        execute 'ALTER TABLE organizations DROP CONSTRAINT organizations_kind_shape'
      end
    end
  end
end
