# frozen_string_literal: true

require 'digest'

module PublicationWaves
  # Chooses the plants a wave publishes (task API-12).
  #
  # Base set: the data source's plants, owned by the data source's own
  # organization, not deleted, published with organization access (legacy
  # visibility private). Excluded: plants already in an active wave and
  # plants with an open source_deletion conflict.
  #
  # Selectors:
  #   quality    the base set filtered by the data source's publication_rule
  #   remaining  the whole base set (later waves)
  #   ids        the base set restricted to the given plant ids
  # An optional limit keeps the first N by id (a canary).
  #
  # The digest is a sha256 over the selector, the rule, the plant ids and the
  # ids of the private images that would be flipped. A dry run prints it and
  # an apply must quote it (EXPECTED_DIGEST), so an apply publishes exactly
  # what the reviewed dry run showed.
  class Selector
    DIGEST_VERSION = 1

    Selection = Struct.new(:plant_ids, :image_ids, :digest, :rule_snapshot, :excluded, keyword_init: true)

    attr_reader :selector

    def initialize(data_source:, selector:, ids: [], limit: nil)
      @data_source = data_source
      @selector = selector.to_s
      @ids = Array(ids).map { |id| id.to_s.strip.downcase }.compact_blank.uniq.sort
      @limit = limit.presence && Integer(limit, exception: false)
      validate!(limit)
    end

    def select
      plant_ids = scope.pluck(:id).sort
      image_ids = private_images(plant_ids).order(:id).pluck(:id)
      Selection.new(plant_ids: plant_ids, image_ids: image_ids, rule_snapshot: rule_snapshot, excluded: excluded_counts,
                    digest: digest(plant_ids, image_ids))
    end

    def params
      { 'ids' => (@ids if @selector == 'ids'), 'limit' => @limit }.compact
    end

    def rule_snapshot
      @data_source.publication_rule
    end

    private

    def validate!(raw_limit)
      raise Refused, "unknown selector #{@selector.inspect}; use #{PublicationWave::SELECTORS.join(', ')}" unless PublicationWave::SELECTORS.include?(@selector)
      raise Refused, 'LIMIT must be a positive integer' if raw_limit.present? && !@limit&.positive?

      validate_selector_inputs!
    end

    def validate_selector_inputs!
      raise Refused, 'selector ids needs at least one plant id (IDS)' if @selector == 'ids' && @ids.empty?
      return unless @selector == 'quality' && rule_snapshot.nil?

      raise Refused, 'selector quality needs a publication_rule on the data source (publication:set_rule)'
    end

    def scope
      selected = case @selector
                 when 'quality' then candidates.where(@data_source.quality_rule.sql_condition)
                 when 'remaining' then candidates
                 else candidates.where(id: @ids)
                 end
      @limit ? selected.order(:id).limit(@limit) : selected
    end

    def base
      Plant.unscoped.where(data_source_id: @data_source.id, owner_organization_id: @data_source.organization_id,
                           deleted_at: nil, publication_state: 'published', access_level: 'organization')
    end

    def candidates
      base.where.not(id: in_active_wave).where.not(id: open_source_deletions)
    end

    def in_active_wave
      PublicationWaveItem.joins(:publication_wave).merge(PublicationWave.active)
                         .where(item_type: 'Plant').select(:item_id)
    end

    def open_source_deletions
      SyncConflict.where(syncable_type: 'Plant', conflict_type: 'source_deletion', status: 'open').select(:syncable_id)
    end

    def excluded_counts
      { 'in_active_wave' => base.where(id: in_active_wave).count,
        'open_source_deletion' => base.where(id: open_source_deletions).count }
    end

    def private_images(plant_ids)
      Image.where(imageable_type: 'Plant', imageable_id: plant_ids, visibility: Image.visibilities[:private])
    end

    def digest(plant_ids, image_ids)
      payload = { 'v' => DIGEST_VERSION, 'data_source_id' => @data_source.id, 'selector' => @selector,
                  'params' => params, 'rule' => rule_snapshot, 'plants' => plant_ids, 'images' => image_ids }
      Digest::SHA256.hexdigest(JSON.generate(payload))
    end
  end
end
