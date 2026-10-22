# frozen_string_literal: true

module PublicationWaves
  # Publishes one wave (task API-12): each selected plant goes from
  # organization access to public access (the OrganizedResource dual-write
  # turns that into legacy visibility public), and its private images become
  # public, one plant per transaction.
  #
  # Dry run (the default) selects and counts, and writes nothing. An apply
  # needs the dry run's digest (expected_digest) and then:
  #   1. creates the wave and one pending item per selected plant, in one
  #      transaction;
  #   2. publishes each pending plant in its own transaction, recording the
  #      exact before (prior) and after (applied) columns of the plant and of
  #      every image it flips;
  #   3. marks the wave applied.
  # It is idempotent and resumable: re-running an applying wave with the same
  # digest continues with the items still pending; re-running an applied wave
  # changes nothing.
  #
  # Images are flipped under no_touching, so the plant gets exactly one new
  # version (its own access change) and no touch versions. Saves skip model
  # validation: a wave changes visibility columns only, and an unrelated
  # pre-existing data problem must not leave a plant half published.
  #
  # The caller holds OpsAdvisoryLock (the rake task takes it).
  class Publisher
    Result = Struct.new(:wave, :applied, :resumed, :digest, :counts, keyword_init: true)

    # options: selector: (required), ids:, limit: (see Selector) and notes:.
    def initialize(data_source:, key:, apply: false, expected_digest: nil, **options)
      @data_source = data_source
      @key = key.to_s
      @expected_digest = expected_digest.to_s.strip.downcase.presence
      @notes = options[:notes].presence
      @apply = apply
      raise Refused, "wave key must match #{PublicationWave::KEY_FORMAT.source}" unless PublicationWave::KEY_FORMAT.match?(@key)
      raise Refused, "NOTES must not contain '@' (no email addresses in the wave ledger)" if @notes.to_s.include?('@')

      @selector = Selector.new(data_source: data_source, **options.except(:notes))
    end

    def run
      wave = PublicationWave.find_by(key: @key)
      wave ? resume(wave) : start
    end

    private

    def start
      selection = @selector.select
      counts = Summary.selection(selection)
      return Result.new(applied: false, resumed: false, digest: selection.digest, counts: counts) unless @apply

      check_digest!(selection.digest)
      raise Refused, 'nothing to publish: the selection is empty' if selection.plant_ids.empty?

      wave = create_wave(selection, counts)
      finish(wave, resumed: false)
    end

    def resume(wave)
      check_resumable!(wave)
      return existing(wave) if !@apply || wave.state == 'applied'

      check_digest!(wave.selection_digest)
      finish(wave, resumed: true)
    end

    def existing(wave) = Result.new(wave: wave, applied: false, resumed: true, digest: wave.selection_digest, counts: Summary.wave(wave))

    def check_resumable!(wave)
      raise Refused, "wave #{wave.key} belongs to another data source" unless wave.data_source_id == @data_source.id
      return if %w[applying applied].include?(wave.state)

      raise Refused, "wave #{wave.key} is #{wave.state}; publish a new wave with a new key"
    end

    def check_digest!(digest)
      raise Refused, 'EXPECTED_DIGEST is required to apply: copy it from the dry run' if @expected_digest.nil?
      return if ActiveSupport::SecurityUtils.secure_compare(@expected_digest, digest)

      raise Refused, 'EXPECTED_DIGEST does not match the current selection: something changed since the dry run. ' \
                     'Run the dry run again and review it.'
    end

    def create_wave(selection, counts)
      PublicationWaves.with_provenance(origin: 'wave_publish', wave: nil, data_source: @data_source) do
        PublicationWave.transaction do
          wave = PublicationWave.create!(key: @key, data_source: @data_source, selector: @selector.selector,
                                         selector_params: @selector.params, rule_snapshot: selection.rule_snapshot,
                                         selection_digest: selection.digest, state: 'applying', counts: { 'selected' => counts },
                                         notes: @notes, published_at: Time.current)
          PublicationWaveItem.insert_pending_plants!(wave, selection.plant_ids)
          wave
        end
      end
    end

    def finish(wave, resumed:)
      PublicationWaves.with_provenance(origin: 'wave_publish', wave: wave, data_source: @data_source) do
        wave.items.where(item_type: 'Plant', state: 'pending').order(:plant_id).pluck(:id).each do |item_id|
          publish_plant(item_id)
        end
        wave.update!(state: 'applied', counts: wave.counts.merge('applied' => Summary.items(wave)))
      end
      Result.new(wave: wave, applied: true, resumed: resumed, digest: wave.selection_digest, counts: Summary.wave(wave))
    end

    def publish_plant(item_id)
      PublicationWave.transaction do
        item = PublicationWaveItem.lock.find(item_id)
        next unless item.state == 'pending'

        plant = Plant.unscoped.lock.find_by(id: item.plant_id)
        next item.update!(state: 'missing') if plant.nil?

        publish!(item, plant)
      end
    end

    def publish!(item, plant)
      prior = PublicationWaves.snapshot(plant)
      return item.update!(state: 'skipped', prior: prior) unless eligible?(plant)

      ActiveRecord::Base.no_touching { publish_images(item.publication_wave, plant) }
      plant.access_level = 'public'
      plant.save!(validate: false)
      item.update!(state: 'applied', prior: prior, applied: PublicationWaves.snapshot(plant))
    end

    def eligible?(plant) = plant.deleted_at.nil? && plant.publication_state == 'published' && plant.access_level == 'organization'

    def publish_images(wave, plant)
      Image.where(imageable_type: 'Plant', imageable_id: plant.id, visibility: Image.visibilities[:private])
           .order(:id).lock.each do |image|
        prior = PublicationWaves.snapshot(image)
        image.visibility = :public
        image.save!(validate: false)
        PublicationWaveItem.create!(publication_wave: wave, item_type: 'Image', item_id: image.id, plant_id: plant.id,
                                    origin: 'publish', state: 'applied', prior: prior,
                                    applied: PublicationWaves.snapshot(image))
      end
    end
  end
end
