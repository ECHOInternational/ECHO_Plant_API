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
    execute(optimalTemperatureRange: '[12,30]', phRange: '[5.5,7.5]')
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

  describe 'range literal validation' do
    it 'rejects degenerate range literals: [.,.]' do
      original = plant.optimal_temperature_range
      result = execute(optimalTemperatureRange: '[.,.]')
      errors = result['data']['updatePlant']['errors']
      expect(errors[0]['field']).to eq 'optimalTemperatureRange'
      expect(errors[0]['code']).to eq 400
      expect(plant.reload.optimal_temperature_range).to eq original
    end

    it 'rejects degenerate range literals: [-,-]' do
      original = plant.optimal_temperature_range
      result = execute(optimalTemperatureRange: '[-,-]')
      errors = result['data']['updatePlant']['errors']
      expect(errors[0]['field']).to eq 'optimalTemperatureRange'
      expect(errors[0]['code']).to eq 400
      expect(plant.reload.optimal_temperature_range).to eq original
    end

    it 'rejects degenerate range literals: [-.,-.] ' do
      original = plant.optimal_temperature_range
      result = execute(optimalTemperatureRange: '[-.,-.]')
      errors = result['data']['updatePlant']['errors']
      expect(errors[0]['field']).to eq 'optimalTemperatureRange'
      expect(errors[0]['code']).to eq 400
      expect(plant.reload.optimal_temperature_range).to eq original
    end

    it 'accepts valid range with empty lower bound [,10]' do
      result = execute(optimalTemperatureRange: '[,10]')
      expect(result['data']['updatePlant']['errors']).to be_empty
      # Postgres [,10] means exclusive lower bound; just verify it was accepted and saved
      expect(plant.reload.optimal_temperature_range).not_to be_nil
    end

    it 'accepts valid range with empty upper bound [5,]' do
      result = execute(optimalTemperatureRange: '[5,]')
      expect(result['data']['updatePlant']['errors']).to be_empty
      # Postgres [5,] means exclusive upper bound; just verify it was accepted and saved
      expect(plant.reload.optimal_temperature_range).not_to be_nil
    end

    it 'accepts valid range with decimals [1.5,2]' do
      result = execute(optimalTemperatureRange: '[1.5,2]')
      expect(result['data']['updatePlant']['errors']).to be_empty
      expect(plant.reload.optimal_temperature_range).to include 1.8
    end

    it 'accepts valid range with negative [-3,4]' do
      result = execute(optimalTemperatureRange: '[-3,4]')
      expect(result['data']['updatePlant']['errors']).to be_empty
      expect(plant.reload.optimal_temperature_range).to include 0
    end
  end
end
