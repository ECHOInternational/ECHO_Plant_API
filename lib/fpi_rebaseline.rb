# frozen_string_literal: true

require Rails.root.join('lib/fpi_data_source')

# Re-stamps the merge base of every FPI plant when the managed attribute set
# changes (fpi-connector schema-delta item 2, backlog R11).
#
# FpiDataSource::PLANT_ATTRIBUTES is a schema: SourceSynchronizer slices both
# sides to it before digesting, so adding or removing a key changes what every
# stored snapshot means. This task brings the snapshots forward:
#
#   snapshot = old.except(*removed).merge(added.index_with { |k| FpiDataSource.empty_value(k) })
#
# The base value of an ADDED key is the key's empty value, never the record's
# current local value. Stamping local as base would make a curator's
# pre-existing value look like upstream's last word, and the next run would
# silently overwrite it with FPI's. With the empty base a curator-filled value
# reads as local_changed and FPI's as incoming_changed, so the record raises a
# conflict (or converges when equal) -- the decision-17 outcome. Existing keys
# are never re-read from local either: that would erase the locally_modified
# state of every curator-edited record.
#
# Writes go through update_columns: no validations, no PaperTrail, no
# updated_at (the EcRecordLinker#stamp precedent). Before writing, id,
# source_snapshot, source_digest and sync_state of every FPI plant are copied
# into a dated backup table so a mistaken run is reversible. Refuses to run
# while any open conflict exists for the data source; must run under a sync
# freeze.
class FpiRebaseline
  class Refused < StandardError; end

  Result = Struct.new(:plants, :added, :removed, :changed, :backup_table, :applied, keyword_init: true)

  def initialize(data_source:, attributes: FpiDataSource::PLANT_ATTRIBUTES, apply: false)
    @data_source = data_source
    @attributes = attributes
    @apply = apply
  end

  def run
    refuse_if_conflicts_open!
    scope = Plant.unscoped.where(data_source_id: @data_source.id)
    added, removed = key_delta(scope)
    result = Result.new(plants: scope.count, added: added, removed: removed, changed: 0, backup_table: nil, applied: @apply)
    return result if added.empty? && removed.empty?

    result.backup_table = back_up(scope) if @apply
    scope.find_each { |plant| result.changed += 1 if restamp!(plant, added, removed) }
    result
  end

  private

  def refuse_if_conflicts_open!
    open = SyncConflict.where(data_source: @data_source, status: 'open').count
    raise Refused, "#{open} open conflict(s) for #{@data_source.name}; resolve them before re-baselining" if open.positive?
  end

  # The new base when the plant's snapshot needed one (written when applying), else nil.
  def restamp!(plant, added, removed)
    old = plant.source_snapshot || {}
    snapshot = old.except(*removed).merge(added.index_with { |k| FpiDataSource.empty_value(k) })
    return if snapshot == old

    plant.update_columns(source_snapshot: snapshot, source_digest: SourceSynchronizer.canonical_digest(snapshot)) if @apply
    snapshot
  end

  # The keys currently stored on the records, compared with the managed set.
  def key_delta(scope)
    stored = scope.where.not(source_snapshot: nil).limit(50).pluck(:source_snapshot).flat_map(&:keys).uniq
    [@attributes - stored, stored - @attributes]
  end

  def back_up(scope)
    table = "fpi_rebaseline_backup_#{Time.now.utc.strftime('%Y%m%d%H%M%S')}"
    sql = ActiveRecord::Base.sanitize_sql_array(
      ["CREATE TABLE #{table} AS SELECT id, source_snapshot, source_digest, sync_state FROM plants WHERE data_source_id = ?", @data_source.id]
    )
    ActiveRecord::Base.connection.execute(sql)
    copied = ActiveRecord::Base.connection.select_value("SELECT count(*) FROM #{table}").to_i
    raise Refused, "backup table #{table} holds #{copied} rows, expected #{scope.count}" unless copied == scope.count

    table
  end
end
