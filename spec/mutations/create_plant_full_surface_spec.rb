# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Create Plant full field surface', type: :graphql_mutation do
  before :each do
    Mobility.locale = nil
  end

  let(:current_user) { build(:user, :readwrite) }

  it 'creates a plant with translatable, scalar, and range fields in one call' do
    query = <<-GRAPHQL
      mutation($input: CreatePlantInput!) {
        createPlant(input: $input) {
          errors { field message code }
          plant { uuid uses lifeCycle optimalRainfallRange }
        }
      }
    GRAPHQL
    result = PlantApiSchema.execute(query, context: { current_user: current_user }, variables: {
                                      input: {
                                        primaryCommonName: 'Velvet bean',
                                        uses: 'Green manure',
                                        lifeCycle: 'ANNUAL',
                                        optimalRainfallRange: '[400,2500]',
                                        language: 'en'
                                      }
                                    })
    plant_result = result['data']['createPlant']['plant']
    created = Plant.find plant_result['uuid']
    expect(created.uses).to eq 'Green manure'
    expect(created.life_cycle).to eq 'annual'
    expect(created.optimal_rainfall_range).to include 1000
  end

  it 'returns a payload error for malformed range literals' do
    query = 'mutation($input: CreatePlantInput!){ createPlant(input: $input){ errors { field code } plant { uuid } } }'
    result = nil
    expect {
      result = PlantApiSchema.execute(query, context: { current_user: current_user }, variables: {
                                        input: { primaryCommonName: 'X', phRange: 'acidic' }
                                      })
    }.not_to change(Plant, :count)
    errors = result['data']['createPlant']['errors']
    expect(errors[0]['field']).to eq 'phRange'
    expect(errors[0]['code']).to eq 400
    expect(result['data']['createPlant']['plant']).to be_nil
  end
end
