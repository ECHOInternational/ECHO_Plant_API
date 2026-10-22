# frozen_string_literal: true

module PublicationWaves
  # Rolls one wave back (task API-13), one plant per transaction.
  #
  # For every applied item: when the row still equals what the wave wrote
  # (applied), the prior columns are put back (restored); when someone changed
  # it since, it is left alone and counted (drift); when the row no longer
  # exists (FpiRollback with FORCE_PUBLIC), it is counted (missing).
  #
  # Sweep: a public image on a restored wave plant that was created after the
  # wave started and is not a wave item (a new upstream image, created public
  # because its plant was public, API-6) is made private and recorded as an
  # unpublish_sweep item, so the plant goes back to exactly what it showed
  # before the wave.
  #
  # Dry run (the default) classifies and counts and writes nothing. Re-running
  # an unpublished wave changes nothing. Images are written under no_touching
  # and saves skip validation, as in the Publisher. The caller holds
  # OpsAdvisoryLock.
  class Unpublisher
    Result = Struct.new(:wave, :applied, :counts, keyword_init: true)

    def initialize(data_source:, key:, apply: false)
      @data_source = data_source
      @key = key.to_s
      @apply = apply
    end

    def run
      wave = PublicationWave.find_by(key: @key) or raise Refused, "no wave #{@key}"
      raise Refused, "wave #{wave.key} belongs to another data source" unless wave.data_source_id == @data_source.id
      return Result.new(wave: wave, applied: false, counts: Summary.wave(wave)) if wave.state == 'unpublished'

      @apply ? apply!(wave) : Result.new(wave: wave, applied: false, counts: preview(wave))
    end

    private

    def apply!(wave)
      PublicationWaves.with_provenance(origin: 'wave_unpublish', wave: wave, data_source: @data_source) do
        wave.update!(state: 'unpublishing')
        plant_ids(wave).each { |plant_id| unpublish_plant(wave, plant_id) }
        wave.update!(state: 'unpublished', unpublished_at: Time.current,
                     counts: wave.counts.merge('unpublished' => Summary.items(wave)))
      end
      Result.new(wave: wave, applied: true, counts: Summary.wave(wave))
    end

    def plant_ids(wave)
      wave.items.where(origin: 'publish', state: 'applied').distinct.order(:plant_id).pluck(:plant_id)
    end

    def unpublish_plant(wave, plant_id)
      PublicationWave.transaction do
        images, plants = applied_items(wave, plant_id).partition { |i| i.item_type == 'Image' }
        ActiveRecord::Base.no_touching { images.each { |item| restore_locked(item) } }
        plant_outcome = plants.first && restore_locked(plants.first)
        ActiveRecord::Base.no_touching { sweep(wave, plant_id) } if %w[restored missing].include?(plant_outcome)
      end
    end

    def applied_items(wave, plant_id)
      wave.items.where(plant_id: plant_id, origin: 'publish', state: 'applied').lock.to_a
    end

    def restore_locked(item)
      restore(item, current_row(item, lock: true))
    end

    # Returns the item's new state.
    def restore(item, record)
      state = outcome(item, record)
      write_prior(record, item.prior) if state == 'restored'
      item.update!(state: state)
      state
    end

    def outcome(item, record)
      return 'missing' if record.nil?

      PublicationWaves.snapshot(record) == item.applied ? 'restored' : 'drift'
    end

    def write_prior(record, prior)
      if record.is_a?(Plant)
        record.assign_attributes(publication_state: prior['publication_state'], access_level: prior['access_level'],
                                 deleted_at: prior['deleted_at'])
      else
        record.visibility = prior['visibility']
      end
      record.save!(validate: false)
    end

    def sweep(wave, plant_id)
      sweep_scope(wave, plant_id).lock.each do |image|
        prior = PublicationWaves.snapshot(image)
        image.visibility = :private
        image.save!(validate: false)
        PublicationWaveItem.create!(publication_wave: wave, item_type: 'Image', item_id: image.id, plant_id: plant_id,
                                    origin: 'unpublish_sweep', state: 'restored', prior: prior,
                                    applied: PublicationWaves.snapshot(image))
      end
    end

    def sweep_scope(wave, plant_id)
      Image.where(imageable_type: 'Plant', imageable_id: plant_id, visibility: Image.visibilities[:public])
           .where(created_at: wave.published_at..)
           .where.not(id: wave.items.where(item_type: 'Image').select(:item_id))
           .order(:id)
    end

    # Read-only twin of apply!: what an apply would do now.
    def preview(wave)
      counts = Hash.new(0)
      wave.items.where(origin: 'publish', state: 'applied').find_each { |item| preview_item(wave, item, counts) }
      Summary.wave(wave).merge('preview' => counts.sort.to_h)
    end

    def preview_item(wave, item, counts)
      state = outcome(item, current_row(item))
      counts["#{item.item_type} would be #{state}"] += 1
      counts['Image would be swept'] += sweep_scope(wave, item.plant_id).count if item.item_type == 'Plant' && state != 'drift'
    end

    def current_row(item, lock: false)
      scope = item.item_type == 'Plant' ? Plant.unscoped : Image.all
      (lock ? scope.lock : scope).find_by(id: item.item_id)
    end
  end
end
