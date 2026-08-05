# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'family query', type: :request do
  let!(:family) do
    Family.importing do
      record = create(:family, name: 'Fabaceae')
      Mobility.with_locale(:en) { record.description = 'Pea family' }
      Mobility.with_locale(:es) { record.description = 'Familia de las leguminosas' }
      record.save!
      record
    end
  end

  let(:global_id) { PlantApiSchema.id_from_object(family, Family, {}) }

  def execute(query, variables = {})
    PlantApiSchema.execute(query, variables: variables, context: { current_user: nil })
  end

  it 'loads a family by its Relay global id' do
    result = execute(<<~GQL, { 'id' => global_id })
      query($id: ID!) { family(id: $id) { name kingdom description } }
    GQL
    expect(result.dig('data', 'family', 'name')).to eq('Fabaceae')
    expect(result.dig('data', 'family', 'description')).to eq('Pea family')
  end

  it 'honours the language argument' do
    result = execute(<<~GQL, { 'id' => global_id })
      query($id: ID!) { family(id: $id, language: "es") { description } }
    GQL
    expect(result.dig('data', 'family', 'description')).to eq('Familia de las leguminosas')
  end

  it 'returns the full translations array' do
    result = execute(<<~GQL, { 'id' => global_id })
      query($id: ID!) { family(id: $id) { translations { locale description } } }
    GQL
    locales = result.dig('data', 'family', 'translations').map { |t| t['locale'] }
    expect(locales).to contain_exactly('en', 'es')
  end
end
