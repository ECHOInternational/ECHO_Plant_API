# frozen_string_literal: true

# Issue #114: six range columns on both plants and varieties carry DB defaults
# that fabricate scientific data. Any record created without explicit values
# for these columns silently looks like it has real measurements:
#
#   n_accumulation_range      int4range DEFAULT '[0,1)'
#   biomass_production_range  numrange  DEFAULT '[0.0,0.0]'
#   optimal_temperature_range int4range DEFAULT '[0,61)'
#   optimal_rainfall_range    int4range DEFAULT '[0,)'
#   optimal_altitude_range    int4range DEFAULT '[0,)'
#   ph_range                  numrange  DEFAULT '[0.0,14.0]'
#
# seasonality_days_range has no default and is left untouched -- it is the
# healthy control that shows what these columns should look like.
#
# This migration does two things in one pass:
#   1. Removes the column default so future INSERTs leave these columns NULL
#      unless a real value is supplied.
#   2. Backfills existing rows: any row whose value exactly equals the old
#      default is set to NULL.
#
# The backfill uses raw `execute` UPDATEs rather than going through the
# ActiveRecord models. This is deliberate: it bypasses PaperTrail (no
# fabricated-default cleanup should show up as a versioned "change" in a
# record's history) and it does not touch updated_at (this is a data
# correction, not an edit).
#
# Caveat (decision recorded in issue #114): a row that was genuinely measured
# and happens to equal the old default (e.g. a real ph_range of exactly
# [0.0,14.0]) is indistinguishable from a fabricated one and will be nulled
# by this migration. That loss is accepted.
class RemoveFabricatedRangeDefaults < ActiveRecord::Migration[8.1]
  # SQL literal (for the raw backfill UPDATE ... WHERE comparison) alongside
  # the equivalent Ruby Range (for change_column_default, matching the
  # literal syntax the original create_plants/create_varieties migrations
  # used -- so `down` reproduces the exact same DDL those migrations did).
  RANGE_DEFAULTS = {
    n_accumulation_range: ["'[0,1)'::int4range", (0..0)],
    biomass_production_range: ["'[0.0,0.0]'::numrange", (0..0)],
    optimal_temperature_range: ["'[0,61)'::int4range", (0..60)],
    optimal_rainfall_range: ["'[0,)'::int4range", (0..)],
    optimal_altitude_range: ["'[0,)'::int4range", (0..)],
    ph_range: ["'[0.0,14.0]'::numrange", (0.0..14.0)]
  }.freeze

  TABLES = %i[plants varieties].freeze

  def up
    TABLES.each do |table|
      RANGE_DEFAULTS.each do |column, (literal, _range)|
        # Backfill first, while the default is still in place, so the
        # comparison below is against the value every un-set row actually has.
        count = exec_update(<<~SQL.squish)
          UPDATE #{table} SET #{column} = NULL WHERE #{column} = #{literal}
        SQL
        say "#{table}.#{column}: nulled #{count} row(s) matching the old default #{literal}", true

        change_column_default table, column, nil
      end
    end
  end

  def down
    # Restores the column defaults only. The rows nulled by #up are NOT
    # restored -- there is no way to tell which NULLs were originally
    # fabricated defaults versus genuinely-missing data, so re-fabricating
    # values would be worse than leaving them NULL. This is accepted; the
    # migration does not raise ActiveRecord::IrreversibleMigration.
    TABLES.each do |table|
      RANGE_DEFAULTS.each do |column, (_literal, range)|
        change_column_default table, column, range
      end
    end
  end
end
