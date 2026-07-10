# frozen_string_literal: true

# Pre-promo 2b: quote-tolerant backfill for old-era YAML payloads.
#
# The v1 repair migration (20260710000000_repair_versions_item_id_to_uuid) backfilled
# 19,884 of 20,188 staging rows. The 304 unresolved rows carry OLD-era PaperTrail YAML
# where the uuid is single-quoted in the payload:
#
#   object (update/destroy):
#     id: '06283413-7115-4abd-9147-1a47f17749c5'
#
#   object_changes (create):
#     id:
#     -
#     - '06283413-7115-4abd-9147-1a47f17749c5'
#
# The v1 regexes required a BARE uuid (no surrounding quotes), so these rows were left
# with item_id NULL. This migration re-runs the same two-source backfill with
# quote-tolerant patterns (the `'?` on each side of the capture group matches either a
# single-quoted or bare uuid). It is a strict superset: bare uuids also match.
#
# Design:
#   - Data-only; no schema changes.
#   - Idempotent: both UPDATE statements guard on WHERE item_id IS NULL.
#   - Safe on empty/fresh databases (dev/test/CI): zero rows matched, zero updated.
#   - Logs three counts via say(): resolved-from-object, resolved-from-changes,
#     still-unresolved.
#   - reversible down: no-op (data-only backfill; no structural change to reverse).
class BackfillVersionsItemIdQuotedUuids < ActiveRecord::Migration[8.1]
  # Extraction expressions, exposed as constants so the tripwire spec can pin the
  # exact SQL against the committed quoted-payload fixture shapes.
  #
  # OBJECT_V2: quote-tolerant form of v1's ITEM_ID_FROM_OBJECT_SQL. The `''?` before
  # and after the capture group matches either a bare uuid or a single-quoted uuid
  # (SQL single-quote literal escaped as '' inside the outer single-quoted pattern).
  # `(?n)^` is PostgreSQL newline-sensitive mode (same as v1): `^` anchors at the
  # start of every line so only a line that begins exactly with `id: ` can match --
  # preventing keys like `plant_id:` from spuriously matching via their suffix.
  ITEM_ID_FROM_OBJECT_SQL_V2 =
    "substring(object from '(?n)^id: ''?([0-9a-f\\-]{36})''?')"

  # OBJECT_CHANGES_V2: quote-tolerant form of v1's ITEM_ID_FROM_OBJECT_CHANGES_SQL.
  # Same `(?n)^` line-start anchor and optional-space after the first `-` as v1;
  # adds `''?` on each side of the capture group to absorb single-quoted uuids.
  ITEM_ID_FROM_OBJECT_CHANGES_SQL_V2 =
    "substring(object_changes from E'(?n)^id:\\n-[ ]?\\n- ''?([0-9a-f\\\\-]{36})''?')"

  def up
    # 1) Backfill from `object` (old-era updates + destroys with quoted uuid).
    from_object = exec_update(<<~SQL.squish)
      UPDATE versions
         SET item_id = (#{ITEM_ID_FROM_OBJECT_SQL_V2})::uuid
       WHERE item_id IS NULL
         AND object IS NOT NULL
         AND (#{ITEM_ID_FROM_OBJECT_SQL_V2}) IS NOT NULL
    SQL

    # 2) Backfill remaining NULLs from `object_changes` (old-era creates with quoted uuid).
    from_changes = exec_update(<<~SQL.squish)
      UPDATE versions
         SET item_id = (#{ITEM_ID_FROM_OBJECT_CHANGES_SQL_V2})::uuid
       WHERE item_id IS NULL
         AND object_changes IS NOT NULL
         AND (#{ITEM_ID_FROM_OBJECT_CHANGES_SQL_V2}) IS NOT NULL
    SQL

    total      = select_value('SELECT COUNT(*) FROM versions').to_i
    unresolved = select_value('SELECT COUNT(*) FROM versions WHERE item_id IS NULL').to_i
    say "versions.item_id quoted-uuid backfill: #{total} rows total", true
    say "  resolved from object (v2):          #{from_object}", true
    say "  resolved from object_changes (v2):  #{from_changes}", true
    say "  still unresolved (item_id NULL):    #{unresolved}", true
  end

  def down
    # Data-only backfill; no structural changes to reverse.
    # Rolling back this migration does NOT restore item_id to NULL for the rows it
    # filled -- that would destroy real data. If a true reversal is required, restore
    # from a pre-migration snapshot.
    say 'BackfillVersionsItemIdQuotedUuids#down: no-op (data-only migration)', true
  end
end
