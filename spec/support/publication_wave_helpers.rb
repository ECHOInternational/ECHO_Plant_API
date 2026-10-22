# frozen_string_literal: true

# Fixtures for the publication-wave specs (include PublicationWaveHelpers): an FPI-like data source with the
# wave-1 rule, and plants and images in the states a wave meets.
module PublicationWaveHelpers
  WAVE_RULE = { 'version' => 1, 'locale' => 'en', 'text_fields' => %w[description uses cultivation],
                'min_text_chars' => 500, 'image_suffices' => true }.freeze

  def wave_org
    @wave_org ||= create(:organization, :real, name: 'Provider Org')
  end

  def wave_source
    @wave_source ||= create(:data_source, organization: wave_org, source_system_key: 'fpi', publication_rule: WAVE_RULE)
  end

  # A private plant of the source. text: characters of English description.
  def source_plant(text: 10, **attrs)
    create(:plant, :private, { data_source_id: wave_source.id, owner_organization_id: wave_org.id,
                               source_organization_id: wave_org.id, description: 'x' * text }.merge(attrs))
  end

  def plant_image(plant, visibility = :private, **attrs)
    create(:image, { imageable: plant, visibility: visibility }.merge(attrs))
  end

  def visibility_state
    plants = Plant.unscoped.order(:id).pluck(:id, :visibility, :publication_state, :access_level, :deleted_at)
    images = Image.order(:id).pluck(:id, :visibility, :imageable_id)
    [plants, images]
  end
end
