# frozen_string_literal: true

require Rails.root.join('lib/fpi_data_source')

# Logical rollback of FPI plants (fpi-connector backlog A30, risk E10): there
# is no physical rollback on the shared database, so this removes what a run
# created across every table that references a plant without a foreign key.
#
# Scope: the plants a given run created (their create version carries the
# run id in its metadata), or every FPI plant when no run id is given. For
# those plants it deletes, in dependency order: record drafts, sync conflicts
# (plus any conflict the run raised on a surviving plant), image rows,
# versions (the plants' own, their children's by root, and any stamped with
# the run id), join rows, and the plants themselves -- with delete_all, so no
# new versions are written on the way out. S3 objects behind image rows are
# not touched here; the image phase owns them.
#
# Publication guard (FPI plan API-16): once waves make FPI plants public,
# removing one takes a page off the public site. An apply therefore refuses
# while any target plant is public or belongs to an active publication wave,
# unless force_public (FORCE_PUBLIC=true) is given. The dry run reports both
# counts without refusing. Forced removal keeps the wave items: they are the
# ledger, and unpublish_wave counts their rows as missing.
#
# Dry run by default: counts only. Rehearse on staging before any production
# use.
class FpiRollback
  JOIN_TABLES = %w[common_names categories_plants antinutrients_plants growth_habits_plants koppen_zones_plants tolerances_plants].freeze

  Plan = Struct.new(:run_id, :plants, :record_drafts, :sync_conflicts, :images, :versions, :joins, :public_plants,
                    :wave_items, :applied, keyword_init: true)

  # Raised when an apply would remove public or wave plants without force_public.
  class Refused < StandardError; end

  def initialize(data_source:, run_id: nil, apply: false, force_public: false)
    @data_source = data_source
    @run_id = run_id
    @apply = apply
    @force_public = force_public
  end

  def run
    ids = plant_ids
    plan = plan_for(ids)
    guard!(plan) if @apply
    delete!(ids) if @apply && ids.any?
    plan
  end

  private

  def plan_for(ids)
    Plan.new(
      run_id: @run_id, plants: ids.size, applied: @apply,
      record_drafts: RecordDraft.where(draftable_type: 'Plant', draftable_id: ids).count,
      sync_conflicts: conflicts(ids).count,
      images: Image.where(imageable_type: 'Plant', imageable_id: ids).count,
      versions: versions(ids).count,
      public_plants: public_plants(ids).count,
      wave_items: active_wave_items(ids).count,
      joins: join_counts(ids)
    )
  end

  def join_counts(ids)
    JOIN_TABLES.to_h { |t| [t, ActiveRecord::Base.connection.select_value(count_sql(t, ids)).to_i] }
  end

  def guard!(plan)
    return if @force_public || (plan.public_plants.zero? && plan.wave_items.zero?)

    raise Refused, "#{plan.public_plants} public plant(s) and #{plan.wave_items} item(s) in an active publication wave " \
                   'would be removed from public view. Unpublish the wave first, or set FORCE_PUBLIC=true.'
  end

  def public_plants(ids)
    Plant.unscoped.where(id: ids, access_level: 'public').or(Plant.unscoped.where(id: ids, visibility: Plant.visibilities[:public]))
  end

  # Items of active waves on the target plants (the plant rows and their images).
  def active_wave_items(ids)
    PublicationWaveItem.joins(:publication_wave).merge(PublicationWave.active).where(plant_id: ids)
  end

  def plant_ids
    scope = Plant.unscoped.where(data_source_id: @data_source.id)
    return scope.pluck(:id) if @run_id.nil?

    created = PaperTrail::Version.where(item_type: 'Plant', event: 'create').where("metadata->>'sync_run_id' = ?", @run_id).pluck(:item_id)
    scope.where(id: created).pluck(:id)
  end

  def conflicts(ids)
    by_plant = SyncConflict.where(syncable_type: 'Plant', syncable_id: ids)
    return by_plant if @run_id.nil?

    by_plant.or(SyncConflict.where(data_source_id: @data_source.id, sync_run_id: @run_id))
  end

  def versions(ids)
    own = PaperTrail::Version.where(item_type: 'Plant', item_id: ids)
    children = PaperTrail::Version.where("metadata->>'root_type' = 'Plant' AND (metadata->>'root_id')::uuid IN (?)", ids.presence || [SecureRandom.uuid])
    scope = own.or(children)
    return scope if @run_id.nil?

    scope.or(PaperTrail::Version.where("metadata->>'sync_run_id' = ?", @run_id))
  end

  def count_sql(table, ids)
    ActiveRecord::Base.sanitize_sql_array(["SELECT count(*) FROM #{table} WHERE plant_id IN (?)", ids.presence || [SecureRandom.uuid]])
  end

  def delete!(ids)
    ActiveRecord::Base.transaction do
      RecordDraft.where(draftable_type: 'Plant', draftable_id: ids).delete_all
      conflicts(ids).delete_all
      Image.where(imageable_type: 'Plant', imageable_id: ids).delete_all
      versions(ids).delete_all
      JOIN_TABLES.each do |table|
        ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(["DELETE FROM #{table} WHERE plant_id IN (?)", ids]))
      end
      Plant.unscoped.where(id: ids).delete_all
    end
  end
end
