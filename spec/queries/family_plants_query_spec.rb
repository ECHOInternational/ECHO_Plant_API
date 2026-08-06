# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'family plants', type: :request do
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }
  let!(:public_plant) do
    create(:plant, :public, family: family, scientific_name: 'Vigna unguiculata', family_names: 'Legume family')
  end
  let!(:private_plant) { create(:plant, :private, family: family, scientific_name: 'Secret bean') }

  let(:global_id) { PlantApiSchema.id_from_object(family, Family, {}) }

  def execute(query, user)
    PlantApiSchema.execute(query, variables: { 'id' => global_id },
                                  context: { current_user: user })
  end

  it 'lists only public plants for an anonymous caller' do
    result = execute(<<~GQL, nil)
      query($id: ID!) { family(id: $id) { plants(first: 10) { totalCount nodes { scientificName } } } }
    GQL
    names = result.dig('data', 'family', 'plants', 'nodes').map { |n| n['scientificName'] }
    expect(names).to eq(['Vigna unguiculata'])
    expect(result.dig('data', 'family', 'plants', 'totalCount')).to eq(1)
  end

  it 'exposes the family from the plant side' do
    plant_id = PlantApiSchema.id_from_object(public_plant, Plant, {})
    result = PlantApiSchema.execute(<<~GQL, variables: { 'id' => plant_id }, context: { current_user: nil })
      query($id: ID!) { plant(id: $id) { family { name } familyNames } }
    GQL
    expect(result.dig('data', 'plant', 'family', 'name')).to eq('Fabaceae')
    # Proves the frozen familyNames field still resolves alongside the new
    # family field, not merely that the query executes without error.
    expect(result.dig('data', 'plant', 'familyNames')).to eq('Legume family')
  end

  it 'returns a null family when the plant has none' do
    orphan = create(:plant, :public, family: nil)
    plant_id = PlantApiSchema.id_from_object(orphan, Plant, {})
    result = PlantApiSchema.execute(<<~GQL, variables: { 'id' => plant_id }, context: { current_user: nil })
      query($id: ID!) { plant(id: $id) { family { name } } }
    GQL
    expect(result.dig('data', 'plant', 'family')).to be_nil
  end

  describe 'pagination order stability' do
    def page_ids(query_string, variables)
      result = PlantApiSchema.execute(query_string, variables: variables.merge('id' => global_id),
                                                    context: { current_user: nil })
      result.dig('data', 'family', 'plants', 'edges').map { |e| e.dig('node', 'id') }
    end

    it 'pages through every record exactly once when scientific names tie and a row is edited mid-paging' do
      # Every plant shares one scientific name, so the sort key can never
      # decide order on its own: only the id tiebreaker can. This is the same
      # hazard PlantsResolver documents -- Family.plants paginates by OFFSET,
      # so page two is a separate query, and Postgres gives no guaranteed order
      # for tied rows between two unordered queries.
      created = Array.new(9) do
        create(:plant, :public, family: family, scientific_name: 'Cucurbita moschata')
      end

      query_string = <<~GQL
        query($id: ID!, $first: Int, $after: String) {
          family(id: $id) { plants(first: $first, after: $after) { edges { node { id } } } }
        }
      GQL

      first_page = page_ids(query_string, { 'first' => 3 })

      # An UPDATE writes a new row version at the end of the heap, so an
      # unordered sequential scan returns it in a different position than it
      # did a moment ago -- this is what turns a missing tiebreaker from
      # theoretical into a record you never see while paging.
      created.first.update!(family_names: 'Cucurbitaceae')

      second_page = page_ids(query_string, { 'first' => 3, 'after' => 'Mw' }) # offset 3
      third_page = page_ids(query_string, { 'first' => 3, 'after' => 'Ng' })  # offset 6

      seen = first_page + second_page + third_page
      expect(seen.uniq.size).to eq(9), "a record was skipped or repeated across pages: #{seen}"
      expect(seen.sort).to eq(created.map { |p| PlantApiSchema.id_from_object(p, Plant, {}) }.sort)
    end
  end

  describe 'the max_page_size cap' do
    it 'clamps first: above 100 down to 100 nodes' do
      Array.new(105) { create(:plant, :public, family: family) }

      result = execute(<<~GQL, nil)
        query($id: ID!) { family(id: $id) { plants(first: 500) { nodes { scientificName } } } }
      GQL

      expect(result.dig('data', 'family', 'plants', 'nodes').size).to eq(100)
    end
  end
end
