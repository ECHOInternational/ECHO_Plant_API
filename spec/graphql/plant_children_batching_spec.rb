# frozen_string_literal: true

require 'rails_helper'

# A page of plants resolves each plant's common names, categories, images,
# organizations and quality bar with one query per page, not one per plant.
# ECHOcommunity's projection snapshot walks every public plant with exactly
# these fields (about 350 pages at 34.7k plants), and the per-plant queries
# were most of its time. The answers must be the ones the per-plant SQL gives:
# the expectations below are computed with that SQL, not with the API.
RSpec.describe 'Plant children batched per page', type: :graphql_query do
  before { Mobility.locale = nil }

  let(:rule) do
    { 'version' => 1, 'locale' => 'en', 'text_fields' => %w[description uses cultivation],
      'min_text_chars' => 500, 'image_suffices' => true }
  end
  let(:source) { create(:data_source, publication_rule: rule) }
  let(:org) { create(:organization, :real) }

  let(:document) do
    <<~GRAPHQL
      query($first: Int, $language: String) {
        plants(first: $first) {
          nodes {
            uuid
            meetsQualityBar
            ownerOrganization { uuid }
            sourceOrganization { uuid }
            commonNames(first: 2) { totalCount pageInfo { hasNextPage } nodes { uuid } }
            allNames: commonNames(first: 300) { totalCount nodes { uuid } }
            languageNames: commonNames(language: $language) { totalCount nodes { uuid } }
            categories(first: 50) { totalCount nodes { uuid } }
            images(first: 200) { pageInfo { hasNextPage } nodes { uuid } }
          }
        }
      }
    GRAPHQL
  end

  def run(user: nil, first: 50, language: 'en')
    result = PlantApiSchema.execute(document, variables: { 'first' => first, 'language' => language },
                                              context: { current_user: user })
    expect(result['errors']).to be_nil
    result.dig('data', 'plants', 'nodes').index_by { |node| node['uuid'] }
  end

  # Plants with a spread of names (primary first, ties on name broken by id,
  # mixed-case languages), images (positions, nulls, private and deleted) and
  # categories (public and private).
  def seed_plant(index, with_source: true, text: 'short')
    plant = create(:plant, :public, description: text, data_source_id: (source.id if with_source),
                                    owner_organization_id: org.id, source_organization_id: org.id)
    seed_names(plant, index)
    seed_images(plant, index)
    seed_categories(plant, index)
    plant
  end

  def seed_names(plant, index)
    [['Beta', 'EN', false], ['Alpha', 'en', false], ['Alpha', 'UND', false], ['Zeta', 'EN', true]].each do |name, lang, pri|
      create(:common_name, plant: plant, name: "#{name} #{index}", language: lang, primary: pri)
    end
    create(:common_name, plant: plant, name: "Gamma #{index}", language: 'FR') if index.even?
  end

  def seed_images(plant, index)
    if index.odd?
      [2, nil, 1].each { |position| create(:image, :public, imageable: plant).update_columns(position: position) }
      create(:image, :private, imageable: plant)
    end
    create(:image, :deleted, imageable: plant) if index == 2
  end

  def seed_categories(plant, index)
    plant.categories << create(:category, :public)
    plant.categories << create(:category, :private) if index.odd?
    plant.categories << create(:category, :public) if index == 3
  end

  def uuids(records)
    records.map { |record| { 'uuid' => record.id } }
  end

  # The per-plant SQL the field resolvers ran before batching.
  def expected_for(plant, user)
    {
      'uuid' => plant.id,
      'meetsQualityBar' => plant.meets_quality_bar?,
      'ownerOrganization' => { 'uuid' => plant.owner_organization_id },
      'sourceOrganization' => { 'uuid' => plant.source_organization_id }
    }.merge(expected_names(plant), expected_children(plant, user))
  end

  def expected_names(plant)
    names = plant.common_names.reorder(primary: :desc, name: :asc, id: :asc).to_a
    language = plant.common_names.reorder(primary: :desc, name: :asc, id: :asc)
                    .where('upper(common_names.language) = upper(?)', 'en').to_a
    { 'commonNames' => { 'totalCount' => names.size, 'pageInfo' => { 'hasNextPage' => names.size > 2 },
                         'nodes' => uuids(names.first(2)) },
      'allNames' => { 'totalCount' => names.size, 'nodes' => uuids(names) },
      'languageNames' => { 'totalCount' => language.size, 'nodes' => uuids(language) } }
  end

  def expected_children(plant, user)
    images = Pundit.policy_scope(user, plant.images).display_ordered.to_a
    categories = Pundit.policy_scope(user, plant.categories).to_a
    { 'categories' => { 'totalCount' => categories.size, 'nodes' => uuids(categories) },
      'images' => { 'pageInfo' => { 'hasNextPage' => false }, 'nodes' => uuids(images) } }
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  it 'answers exactly what the per-plant queries answer, for an anonymous caller' do
    plants = (1..4).map { |i| seed_plant(i) } + [seed_plant(5, text: 'x' * 600), seed_plant(6, with_source: false)]
    nodes = run
    plants.each { |plant| expect(nodes.fetch(plant.id)).to eq(expected_for(plant, nil)) }
    expect(nodes.values.pluck('meetsQualityBar')).to include(true, false)
  end

  it 'answers exactly what the per-plant queries answer, for a caller who reads private children' do
    plants = (1..3).map { |i| seed_plant(i) }
    user = build(:user, :superadmin)
    nodes = run(user: user)
    plants.each { |plant| expect(nodes.fetch(plant.id)).to eq(expected_for(plant, user)) }
    expect(nodes.fetch(plants.first.id).dig('images', 'nodes').size).to eq 4
  end

  it 'filters names by language case-insensitively' do
    plant = seed_plant(2)
    expect(run(language: 'fr').dig(plant.id, 'languageNames', 'totalCount')).to eq 1
    expect(run(language: 'EN').dig(plant.id, 'languageNames', 'totalCount')).to eq 3
  end

  it 'issues the same number of queries for a page of 2 plants and a page of 6' do
    (1..6).each { |i| seed_plant(i) }
    small = count_queries { run(first: 2) }
    large = count_queries { run(first: 6) }
    expect(large).to eq small
  end

  it 'resolves a single plant the same way' do
    plant = seed_plant(3)
    gid = PlantApiSchema.id_from_object(plant, Types::PlantType, {})
    result = PlantApiSchema.execute(
      'query($id: ID!) { plant(id: $id) { categories { totalCount } images { nodes { uuid } } ' \
      'commonNames(first: 1) { totalCount pageInfo { hasNextPage } nodes { uuid } } } }',
      variables: { 'id' => gid }, context: { current_user: nil }
    )
    expect(result['errors']).to be_nil
    expected = expected_for(plant, nil)
    expect(result.dig('data', 'plant', 'categories', 'totalCount')).to eq expected.dig('categories', 'totalCount')
    expect(result.dig('data', 'plant', 'images', 'nodes')).to eq expected.dig('images', 'nodes')
    expect(result.dig('data', 'plant', 'commonNames', 'totalCount')).to eq 4
    expect(result.dig('data', 'plant', 'commonNames', 'pageInfo', 'hasNextPage')).to be true
  end
end
