# frozen_string_literal: true

class CreateFamilies < ActiveRecord::Migration[8.1]
  def change
    create_table :families, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :name, null: false
      t.string :col_id
      t.string :kingdom, null: false
      t.string :plant_type
      t.string :status, null: false, default: 'accepted'
      t.references :superseded_by, type: :uuid, foreign_key: { to_table: :families }
      t.string :classification_source, null: false
      t.string :classification_version, null: false
      t.date :snapshot_date, null: false
      t.string :storage_physiology
      t.string :seed_longevity
      t.integer :seed_banking_rank
      t.jsonb :translations, default: {}, null: false
      t.timestamps
    end

    add_index :families, 'lower(name)', unique: true, name: 'index_families_on_lower_name'
    add_index :families, :col_id, unique: true, where: 'col_id IS NOT NULL',
                                  name: 'index_families_on_col_id'
    add_index :families, :status
    add_index :families, :plant_type

    # Database-level immutability. The list may only be changed by the importer,
    # which sets families.import_mode for the duration of its transaction.
    # A model callback alone is not enough: insert_all, delete_all and a console
    # session all bypass it.
    #
    # SUPERSEDED: this function body is broken (it references NEW during a
    # DELETE and OLD during an INSERT, both unassigned on the side that
    # doesn't apply) and is replaced by
    # 20260806000003_fix_families_locked_list_trigger_delete.rb. Do not read
    # this migration alone and believe it describes the function currently
    # installed; read migration 3 too.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE FUNCTION families_reject_list_change() RETURNS trigger AS $$
          BEGIN
            IF current_setting('families.import_mode', true) IS DISTINCT FROM 'on' THEN
              RAISE EXCEPTION
                'families is a locked reference list; % is only permitted during an import',
                TG_OP;
            END IF;
            -- Permitted writes must proceed: returning NULL from a BEFORE row
            -- trigger would silently skip the row instead.
            RETURN COALESCE(NEW, OLD);
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER families_locked_list
            BEFORE INSERT OR DELETE ON families
            FOR EACH ROW EXECUTE PROCEDURE families_reject_list_change();
        SQL
      end
      dir.down do
        execute <<~SQL
          DROP TRIGGER IF EXISTS families_locked_list ON families;
          DROP FUNCTION IF EXISTS families_reject_list_change();
        SQL
      end
    end
  end
end
