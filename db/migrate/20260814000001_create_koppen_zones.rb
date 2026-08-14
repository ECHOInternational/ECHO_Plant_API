# frozen_string_literal: true

# The Köppen-Geiger climate-zone lookup (D-017), modelled on families.
#
# Three levels, self-parented: 5 groups, 8 subgroups and 30 classes, plus the
# two `n` fog variants ECHOcommunity already uses - 45 rows. The subgroup level
# (`Cf`, `BS`, ...) is not part of the published classification, but it carries
# 306 of ECHOcommunity's 512 existing assignments: recording a plant as `Cf`
# states what is known without asserting a summer-temperature class it does not
# have. `authoritative` marks the 30 published classes so the distinction stays
# visible rather than being flattened away.
#
# `code` is the natural key, as `name` is for families. Codes are defined by the
# classification and do not change; the translated names on top are ECHO's and
# do.
class CreateKoppenZones < ActiveRecord::Migration[8.1]
  def change
    create_table :koppen_zones, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :code, null: false
      t.string :level, null: false
      t.references :parent, type: :uuid, foreign_key: { to_table: :koppen_zones }
      t.boolean :authoritative, null: false, default: false
      t.string :classification_source, null: false
      t.string :classification_version, null: false
      t.date :snapshot_date, null: false
      t.integer :position
      t.jsonb :translations, default: {}, null: false
      t.timestamps
    end

    # Codes are case-significant in the classification (`Cfa` not `CFA`), but a
    # unique index on the exact string is what protects the natural key; the
    # lower() index additionally stops `cfa` and `Cfa` coexisting.
    add_index :koppen_zones, 'lower(code)', unique: true,
                                            name: 'index_koppen_zones_on_lower_code'
    add_index :koppen_zones, :level
    add_index :koppen_zones, :authoritative

    # Database-level immutability, exactly as for families: a model callback
    # alone is bypassed by insert_all, delete_all and a console session.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE FUNCTION koppen_zones_reject_list_change() RETURNS trigger AS $$
          BEGIN
            IF current_setting('koppen_zones.import_mode', true) IS DISTINCT FROM 'on' THEN
              RAISE EXCEPTION
                'koppen_zones is a locked reference list; % is only permitted during an import',
                TG_OP;
            END IF;
            -- Branch on TG_OP rather than COALESCE(NEW, OLD): NEW is unassigned
            -- during a DELETE and OLD during an INSERT, and merely referencing
            -- the unassigned side raises before COALESCE can evaluate it. This
            -- is the bug families migration 3 had to go back and fix.
            IF TG_OP = 'DELETE' THEN
              RETURN OLD;
            ELSE
              RETURN NEW;
            END IF;
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER koppen_zones_locked_list
            BEFORE INSERT OR DELETE ON koppen_zones
            FOR EACH ROW EXECUTE PROCEDURE koppen_zones_reject_list_change();
        SQL
      end
      dir.down do
        execute <<~SQL
          DROP TRIGGER IF EXISTS koppen_zones_locked_list ON koppen_zones;
          DROP FUNCTION IF EXISTS koppen_zones_reject_list_change();
        SQL
      end
    end
  end
end
