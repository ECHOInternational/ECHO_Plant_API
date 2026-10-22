# frozen_string_literal: true

require 'rails_helper'

# FPI plan API-10 / section 3.2: data_sources.publication_rule is the single
# quality setting. PublicationRule#sql_condition (the wave selector's form) and
# PublicationRule#met_by? (Plant#meets_quality_bar?, meetsQualityBar) must
# always agree; this spec keeps them in parity on the edge cases.
RSpec.describe PublicationRule do
  let(:rule_hash) do
    { 'version' => 1, 'locale' => 'en', 'text_fields' => %w[description uses cultivation],
      'min_text_chars' => 500, 'image_suffices' => true }
  end
  let(:rule) { described_class.new(rule_hash) }
  let(:source) { create(:data_source, publication_rule: rule_hash) }

  def plant_with(translations: {}, **attrs)
    plant = create(:plant, data_source_id: source.id, **attrs)
    # Raw write: Mobility stores an empty container as NULL, which the column forbids.
    Plant.where(id: plant.id).update_all(['translations = CAST(? AS jsonb)', translations.to_json])
    plant.reload
  end

  def en(**fields)
    { 'en' => fields.transform_keys(&:to_s) }
  end

  let!(:cases) do
    {
      chars499: plant_with(translations: en(description: 'a' * 300, uses: 'b' * 199)),
      chars500: plant_with(translations: en(description: 'a' * 300, uses: 'b' * 100, cultivation: 'c' * 100)),
      multibyte500: plant_with(translations: en(description: "\u00e9" * 500)),
      other_field_only: plant_with(translations: en(habitat: 'h' * 900)),
      other_locale_only: plant_with(translations: { 'fr' => { 'description' => 'd' * 900 } }),
      empty_translations: plant_with(translations: {}),
      image_only: plant_with.tap { |p| create(:image, :public, imageable: p) },
      private_image_only: plant_with.tap { |p| create(:image, :private, imageable: p) },
      deleted_image_only: plant_with.tap { |p| create(:image, :deleted, imageable: p) },
      variety_image_only: plant_with.tap { |p| create(:image, imageable: create(:variety, plant: p)) }
    }
  end

  let(:expected_meeting) { %i[chars500 multibyte500 image_only private_image_only] }

  it 'met_by? accepts exactly the expected edge cases' do
    met = cases.select { |_, plant| rule.met_by?(plant) }.keys
    expect(met).to match_array(expected_meeting)
  end

  it 'sql_condition selects exactly what met_by? accepts' do
    ids = Plant.where(id: cases.values.map(&:id)).where(rule.sql_condition).pluck(:id)
    expect(ids).to match_array(expected_meeting.map { |k| cases[k].id })
  end

  it 'does not let an image suffice when image_suffices is false' do
    strict = described_class.new(rule_hash.merge('image_suffices' => false))
    expect(strict.met_by?(cases[:image_only])).to be false
    expect(Plant.where(id: cases[:image_only].id).where(strict.sql_condition)).to be_empty
  end

  describe 'Plant#meets_quality_bar?' do
    it 'applies the data source rule' do
      expect(cases[:chars499].meets_quality_bar?).to be false
      expect(cases[:chars500].meets_quality_bar?).to be true
    end

    it 'is true for a plant without a data source (ECHO) or whose source has no rule' do
      expect(create(:plant).meets_quality_bar?).to be true
      ruleless = create(:data_source, publication_rule: nil)
      expect(create(:plant, data_source_id: ruleless.id).meets_quality_bar?).to be true
    end
  end

  describe 'validation' do
    it 'accepts the FPI rule' do
      expect(rule).to be_valid
    end

    [
      ['an unknown version', { 'version' => 2 }],
      ['a text field that is not a translated plant field', { 'text_fields' => ['description; DROP TABLE plants'] }],
      ['an empty text field list', { 'text_fields' => [] }],
      ['a negative minimum', { 'min_text_chars' => -1 }],
      ['a non-integer minimum', { 'min_text_chars' => '500' }],
      ['a malformed locale', { 'locale' => "en'--" }],
      ['a non-boolean image_suffices', { 'image_suffices' => 'yes' }]
    ].each do |label, change|
      it "rejects #{label}" do
        expect(described_class.new(rule_hash.merge(change))).not_to be_valid
      end
    end

    it 'makes DataSource invalid with a bad rule' do
      expect(build(:data_source, publication_rule: rule_hash.merge('version' => 9))).not_to be_valid
    end
  end
end
