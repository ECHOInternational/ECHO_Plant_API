# frozen_string_literal: true

# Repairs the six-year-old versions.item_id dysfunction.
#
# Every model PK is a uuid, but versions.item_id was declared bigint. PaperTrail
# stores record.id.to_i, and "de68e499-...".to_i == 0, so EVERY version row since
# 2020 has item_id = 0. The polymorphic `record.versions` association therefore
# matches nothing; history was only reachable by scanning item_type.
#
# This migration converts item_id to uuid and backfills the true record id out of
# the YAML payloads (which retained it all along):
#   * `object` (updates/destroys): a line-anchored `id: <uuid>` line.
#   * `object_changes` (creates):  an `id:` change tuple `id:\n-\n- <uuid>`.
#
# It is safe on empty/fresh databases (dev/test/CI) and idempotent-safe against a
# staging snapshot: it only backfills rows whose item_uuid is still NULL, and it
# logs the resulting counts so the ECS migrate task output is auditable.
class RepairVersionsItemIdToUuid < ActiveRecord::Migration[8.1]
  # Extraction expressions, exposed as constants so the tripwire spec can pin the
  # exact SQL against the committed PT-10 fixture payload shape.
  #
  # OBJECT: line-anchored `id: <uuid>`. `(?n)` is PostgreSQL newline-sensitive mode
  # (^ matches at the start of every line), so it matches the `id:` line even though
  # the document opens with `---`. Verified on the compose PostgreSQL 9.6 and against
  # PaperTrail 17 update/destroy payloads.
  ITEM_ID_FROM_OBJECT_SQL = "substring(object from '(?n)^id: ([0-9a-f\\-]{36})')"

  # OBJECT_CHANGES: the create-tuple `id:\n- \n- <uuid>` / `id:\n-\n- <uuid>`. The
  # optional space after the first `-` absorbs both YAML spellings PaperTrail emits.
  ITEM_ID_FROM_OBJECT_CHANGES_SQL =
    "substring(object_changes from E'id:\\n-[ ]?\\n- ([0-9a-f\\\\-]{36})')"

  def up
    add_column :versions, :item_uuid, :uuid

    # 1) Backfill from `object` (updates + destroys).
    from_object = exec_update(<<~SQL.squish)
      UPDATE versions
         SET item_uuid = (#{ITEM_ID_FROM_OBJECT_SQL})::uuid
       WHERE item_uuid IS NULL
         AND object IS NOT NULL
         AND (#{ITEM_ID_FROM_OBJECT_SQL}) IS NOT NULL
    SQL

    # 2) Backfill remaining NULLs from `object_changes` (creates).
    from_changes = exec_update(<<~SQL.squish)
      UPDATE versions
         SET item_uuid = (#{ITEM_ID_FROM_OBJECT_CHANGES_SQL})::uuid
       WHERE item_uuid IS NULL
         AND object_changes IS NOT NULL
         AND (#{ITEM_ID_FROM_OBJECT_CHANGES_SQL}) IS NOT NULL
    SQL

    total       = select_value('SELECT COUNT(*) FROM versions').to_i
    unresolved  = select_value('SELECT COUNT(*) FROM versions WHERE item_uuid IS NULL').to_i
    say "versions.item_id repair: #{total} rows total", true
    say "  backfilled from object:         #{from_object}", true
    say "  backfilled from object_changes: #{from_changes}", true
    say "  unresolved (item_uuid NULL):    #{unresolved}", true

    # Swap the columns: drop the all-zeros bigint, promote the uuid into its place,
    # and recreate the index under the identical name/shape it had before.
    remove_index :versions, column: %i[item_type item_id],
                            name: :index_versions_on_item_type_and_item_id
    remove_column :versions, :item_id
    rename_column :versions, :item_uuid, :item_id
    add_index :versions, %i[item_type item_id],
              name: :index_versions_on_item_type_and_item_id
  end

  def down
    # The original item_id was all zeros; there is nothing meaningful to restore.
    # Rebuild a bigint item_id (defaulting to 0, matching the historical state) and
    # its index so the schema round-trips.
    remove_index :versions, column: %i[item_type item_id],
                            name: :index_versions_on_item_type_and_item_id
    rename_column :versions, :item_id, :item_uuid
    # A NOT NULL column needs a default to backfill existing rows; we then drop the
    # default to match the original NOT-NULL-no-default column shape.
    add_column :versions, :item_id, :bigint, null: false, default: 0
    change_column_default :versions, :item_id, nil
    remove_column :versions, :item_uuid
    add_index :versions, %i[item_type item_id],
              name: :index_versions_on_item_type_and_item_id
  end
end
