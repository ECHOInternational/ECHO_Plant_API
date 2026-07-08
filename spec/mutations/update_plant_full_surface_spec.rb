# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Plant full field surface', type: :graphql_mutation do
  before :each do
    Mobility.locale = nil
  end

  let(:current_user) { build(:user, :readwrite) }
  let!(:plant) { create(:plant, owned_by: current_user.email, created_by: current_user.email) }
  let(:plant_gid) { PlantApiSchema.id_from_object(plant, Plant, {}) }

  def execute(input)
    query = <<-GRAPHQL
      mutation($input: UpdatePlantInput!) {
        updatePlant(input: $input) {
          errors { field message code }
          plant {
            uuid uses cultivation lifeCycle earlyGrowthPhase
            hasEdibleGreenLeaves optimalTemperatureRange phRange
          }
        }
      }
    GRAPHQL
    PlantApiSchema.execute(query, context: { current_user: current_user },
                                  variables: { input: { plantId: plant_gid }.merge(input) })
  end

  it 'updates newly exposed translatable fields in the requested language' do
    execute(uses: 'Ground cover', cultivation: 'Direct seed', language: 'en')
    execute(uses: 'Cobertura', language: 'es')
    expect(plant.reload.uses).to eq 'Ground cover'
    expect(plant.cultivation).to eq 'Direct seed'
    Mobility.with_locale(:es) { expect(plant.uses).to eq 'Cobertura' }
  end

  it 'updates enum and boolean scalars' do
    result = execute(lifeCycle: 'PERENNIAL', earlyGrowthPhase: 'FAST', hasEdibleGreenLeaves: true)
    plant_result = result['data']['updatePlant']['plant']
    expect(plant_result['lifeCycle']).to eq 'PERENNIAL'
    expect(plant_result['earlyGrowthPhase']).to eq 'FAST'
    expect(plant_result['hasEdibleGreenLeaves']).to be true
    expect(plant.reload.life_cycle).to eq 'perennial'
  end

  it 'round-trips range literals' do
    result = execute(optimalTemperatureRange: '[12,30]', phRange: '[5.5,7.5]')
    plant_result = result['data']['updatePlant']['plant']
    expect(plant_result['errors']).to be_nil if plant_result.key?('errors')
    expect(plant.reload.optimal_temperature_range).to include 20
    expect(plant.optimal_temperature_range).to_not include 40
    expect(plant.ph_range).to include 6.0
  end

  it 'returns a payload error for malformed range literals without saving' do
    original = plant.optimal_temperature_range
    result = execute(optimalTemperatureRange: 'warm-ish')
    errors = result['data']['updatePlant']['errors']
    expect(errors[0]['field']).to eq 'optimalTemperatureRange'
    expect(errors[0]['code']).to eq 400
    expect(plant.reload.optimal_temperature_range).to eq original
  end

  it 'still rejects updates from non-owners' do
    other = build(:user, :readwrite)
    query = 'mutation($input: UpdatePlantInput!){ updatePlant(input: $input){ plant { uuid } } }'
    result = PlantApiSchema.execute(query, context: { current_user: other },
                                           variables: { input: { plantId: plant_gid, uses: 'x' } })
    expect(result['errors'][0]['extensions']['code']).to eq 403
  end
end
