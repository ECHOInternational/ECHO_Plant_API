# frozen_string_literal: true

# Display order of the images inside one imageable (images.position, 1-based).
#
# The backfill gives every image without a position one, per parent, in this
# order:
#
#   1. images without the 'Drawing' image attribute before those with it
#      (photographs lead; a drawing is never the lead picture),
#   2. the FPI source order: the numeric ROWID of source_record_id
#      ('photos:N' / 'drawings:N'), images without one after,
#   3. created_at, oldest first,
#   4. id, so the order is total.
#
# The Drawing tag is matched by its English name in raw SQL, never through the
# Mobility locale of the caller. The update is raw SQL on purpose: it writes no
# PaperTrail versions and leaves updated_at alone (it is a display-order
# backfill, not an edit). It is resumable: rows that already have a position
# keep it, and unpositioned rows of the same parent are numbered after the
# current maximum.
#
# Used by the AddPositionToImages migration; safe to run again by hand
# (`ImagePositions.backfill!`) if rows ever end up without a position.
module ImagePositions
  DRAWING_NAME = 'Drawing'

  RANK_ORDER = <<~SQL.squish
    EXISTS (
      SELECT 1 FROM image_attributes_images iai
      JOIN image_attributes a ON a.id = iai.image_attribute_id
      WHERE iai.image_id = i.id AND a.translations->'en'->>'name' = '#{DRAWING_NAME}'),
    CASE WHEN i.source_record_id ~ '^(photos|drawings):[0-9]{1,18}$'
         THEN split_part(i.source_record_id, ':', 2)::bigint END NULLS LAST,
    i.created_at, i.id
  SQL

  module_function

  # Walks the parents in (imageable_type, imageable_id) keyset order,
  # batch_size parents per UPDATE, each in its own short transaction.
  # Returns the number of rows positioned.
  def backfill!(connection: ActiveRecord::Base.connection, batch_size: 500)
    total = 0
    last = nil
    while (upper = batch_upper_bound(connection, last, batch_size))
      connection.transaction { total += position_range(connection, last, upper) }
      last = upper
    end
    total
  end

  def batch_upper_bound(connection, last, batch_size)
    rows = connection.select_rows(<<~SQL.squish)
      SELECT imageable_type, imageable_id FROM (
        SELECT DISTINCT imageable_type, imageable_id FROM images
        WHERE position IS NULL #{after_clause(connection, last, 'images')}
        ORDER BY imageable_type, imageable_id
        LIMIT #{Integer(batch_size)}
      ) parents
      ORDER BY imageable_type DESC, imageable_id DESC
      LIMIT 1
    SQL
    rows.first
  end

  def position_range(connection, last, upper)
    connection.update(<<~SQL.squish)
      UPDATE images SET position = ranked.position
      FROM (
        SELECT i.id,
               COALESCE(placed.max_position, 0)
                 + ROW_NUMBER() OVER (PARTITION BY i.imageable_type, i.imageable_id ORDER BY #{RANK_ORDER}) AS position
        FROM images i
        LEFT JOIN LATERAL (
          SELECT MAX(p.position) AS max_position FROM images p
          WHERE p.imageable_type = i.imageable_type AND p.imageable_id = i.imageable_id
        ) placed ON true
        WHERE i.position IS NULL
          #{after_clause(connection, last, 'i')}
          AND (i.imageable_type, i.imageable_id) <= (#{connection.quote(upper[0])}, #{connection.quote(upper[1])}::uuid)
      ) ranked
      WHERE images.id = ranked.id
    SQL
  end

  def after_clause(connection, last, table)
    return '' unless last

    "AND (#{table}.imageable_type, #{table}.imageable_id) > (#{connection.quote(last[0])}, #{connection.quote(last[1])}::uuid)"
  end
end
