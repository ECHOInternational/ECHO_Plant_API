# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Create Variety full field surface', type: :graphql_mutation do
  before :each do
    Mobility.locale = nil
  end

  let(:current_user) { build(:user, :readwrite) }
  let!(:plant) { create(:plant, :public) }
  let(:plant_gid) { PlantApiSchema.id_from_object(plant, Plant, {}) }

  it 'creates a variety with translatable and scalar fields in one call' do
    query = <<-GRAPHQL
      mutation($input: CreateVarietyInput!) {
        createVariety(input: $input) {
          errors { field message code }
          variety { uuid name uses hasEdibleMatureFruit }
        }
      }
    GRAPHQL
    result = PlantApiSchema.execute(query, context: { current_user: current_user }, variables: {
                                      input: {
                                        plantId: plant_gid,
                                        name: 'Early Giant',
                                        uses: 'Fresh market',
                                        hasEdibleMatureFruit: true,
                                        language: 'en'
                                      }
                                    })
    variety_result = result['data']['createVariety']['variety']
    created = Variety.find variety_result['uuid']
    expect(created.name).to eq 'Early Giant'
    expect(created.uses).to eq 'Fresh market'
    expect(created.has_edible_mature_fruit).to be true
  end
end
