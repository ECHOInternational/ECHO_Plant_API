# frozen_string_literal: true

class CreatePrincipals < ActiveRecord::Migration[8.1]
  def change
    create_table :principals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :identity_issuer, null: false
      t.string :external_uid
      t.string :email, null: false
      t.string :display_name
      t.string :kind, null: false, default: "human"
      t.timestamptz :last_authenticated_at
      t.timestamps
    end

    # Unique partial index: (issuer, uid) only when uid is present
    add_index :principals, %i[identity_issuer external_uid],
              unique: true,
              where: "external_uid IS NOT NULL",
              name: "index_principals_on_issuer_and_uid_partial"

    # Non-unique index on email (legacy emails may collide)
    add_index :principals, :email,
              name: "index_principals_on_email"
  end
end
