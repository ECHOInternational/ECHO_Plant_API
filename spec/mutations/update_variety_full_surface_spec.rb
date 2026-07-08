# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Variety full field surface', type: :graphql_mutation do
  before :each do
    Mobility.locale = nil
  end

  let(:current_user) { build(:user, :readwrite) }
  let!(:variety) { create(:variety, owned_by: current_user.email, created_by: current_user.email) }
  let(:variety_gid) { PlantApiSchema.id_from_object(variety, Variety, {}) }

  def execute(input)
    query = <<-GRAPHQL
      mutation($input: UpdateVarietyInput!) {
        updateVariety(input: $input) {
          errors { field message code }
          variety { uuid uses canBeUsedForFodder optimalAltitudeRange }
        }
      }
    GRAPHQL
    PlantApiSchema.execute(query,
                           context: { current_user: current_user },
                           variables: { input: { varietyId: variety_gid }.merge(input) })
  end

  it 'updates translatable fields in the requested language' do
    execute(uses: 'Trellised production', language: 'en')
    execute(uses: 'Producción en espaldera', language: 'es')
    expect(variety.reload.uses).to eq 'Trellised production'
    Mobility.with_locale(:es) { expect(variety.uses).to eq 'Producción en espaldera' }
  end

  it 'round-trips plantingInstructions via translations' do
    query = <<-GRAPHQL
      mutation($input: UpdateVarietyInput!) {
        updateVariety(input: $input) {
          errors { field message code }
          variety { translations { locale plantingInstructions } }
        }
      }
    GRAPHQL
    result = PlantApiSchema.execute(query,
                                    context: { current_user: current_user },
                                    variables: {
                                      input: {
                                        varietyId: variety_gid,
                                        plantingInstructions: 'Sow after last frost',
                                        language: 'en'
                                      }
                                    })
    translations = result['data']['updateVariety']['variety']['translations']
    en_translation = translations.find { |t| t['locale'] == 'en' }
    expect(en_translation['plantingInstructions']).to eq 'Sow after last frost'
  end

  it 'updates booleans and ranges' do
    result = execute(canBeUsedForFodder: true, optimalAltitudeRange: '[0,1500]')
    variety_result = result['data']['updateVariety']['variety']
    expect(variety_result['canBeUsedForFodder']).to be true
    expect(variety.reload.optimal_altitude_range).to include 1000
  end

  it 'returns a payload error for malformed range literals without saving' do
    original = variety.optimal_altitude_range
    result = execute(optimalAltitudeRange: 'high')
    errors = result['data']['updateVariety']['errors']
    expect(errors[0]['field']).to eq 'optimalAltitudeRange'
    expect(errors[0]['code']).to eq 400
    expect(variety.reload.optimal_altitude_range).to eq original
  end
end
