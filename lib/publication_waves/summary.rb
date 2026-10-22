# frozen_string_literal: true

module PublicationWaves
  # The counts a wave report prints (tasks API-12, API-13). COUNTS ONLY: this
  # repository is public and so are its GitHub Actions logs, so nothing here
  # may carry a name, an email, an organization or a principal. Every value is
  # an integer, and the keys are fixed strings. spec/lib/publication_waves/
  # report_pii_spec.rb proves the printed reports contain no '@' and no
  # organization name.
  module Summary
    NORMALISED_NAME = "lower(btrim(regexp_replace(%<col>s, '\\s+', ' ', 'g')))"

    module_function

    def selection(selection)
      plants = Plant.unscoped.where(id: selection.plant_ids)
      { 'plants' => selection.plant_ids.size, 'images' => selection.image_ids.size }
        .merge(safety(plants))
        .merge('echo_twins' => twins(plants), 'open_drafts' => open_drafts(selection.plant_ids))
        .merge(selection.excluded.transform_keys { |reason| "excluded_#{reason}" })
    end

    def open_drafts(plant_ids)
      RecordDraft.where(draftable_type: 'Plant', draftable_id: plant_ids).count
    end

    def safety(plants)
      { 'safety_poisonous' => plants.where(safety_level: 'poisonous').count,
        'safety_caution' => plants.where(safety_level: 'caution').count,
        'edibility_uncertain_only' => plants.where(safety_level: 'none', edibility_uncertain: true).count }
    end

    # Selected plants whose normalised scientific name equals that of a
    # public plant from another source (an ECHO sheet, plan decision Q4).
    def twins(plants)
      mine = format(NORMALISED_NAME, col: 'plants.scientific_name')
      theirs = format(NORMALISED_NAME, col: 'other.scientific_name')
      plants.where(<<~SQL.squish).count
        EXISTS (SELECT 1 FROM plants other
                WHERE other.visibility = #{Plant.visibilities[:public]}
                  AND other.data_source_id IS DISTINCT FROM plants.data_source_id
                  AND #{theirs} = #{mine})
      SQL
    end

    # Item counts by type and state, e.g. {"Plant applied" => 8172}.
    def items(wave)
      wave.items.group(:item_type, :origin, :state).count.to_h do |(type, origin, state), count|
        ["#{type} #{origin} #{state}", count]
      end.sort.to_h
    end

    def wave(wave)
      (wave.counts || {}).merge('items' => items(wave))
    end
  end
end
