# frozen_string_literal: true

require 'rails_helper'

# The safety concept, authority, habitat and notes arrive through the shared
# PlantEditableArguments, so createPlant, updatePlant and saveAsDraft accept
# them with no other mutation change (schema-delta items 5, 6, 17).
RSpec.describe 'Update Plant Mutation: safety, authority, habitat, notes', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let(:plant) { create(:plant, owned_by: current_user.email, created_by: current_user.email) }
  let(:query_string) do
    <<-GRAPHQL
      mutation($input: UpdatePlantInput!) {
        updatePlant(input: $input) {
          errors { field message code }
          plant {
            scientificNameAuthority safetyLevel safetyWarning edibilityUncertain safetyNote habitat notes
          }
        }
      }
    GRAPHQL
  end

  before { Mobility.locale = nil }

  def update(**input)
    plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
    PlantApiSchema.execute(query_string, context: { current_user: current_user },
                                         variables: { input: { plantId: plant_id, language: 'en' }.merge(input) })
  end

  it 'sets every new attribute in one call' do
    result = update(safetyLevel: 'CAUTION', edibilityUncertain: true, safetyNote: 'Seeds (POISONOUS)',
                    scientificNameAuthority: '(L.) Merr.', habitat: 'Tropical.', notes: 'n')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])
    expect(result.dig('data', 'updatePlant', 'plant')).to eq(
      'scientificNameAuthority' => '(L.) Merr.', 'safetyLevel' => 'CAUTION', 'safetyWarning' => true,
      'edibilityUncertain' => true, 'safetyNote' => 'Seeds (POISONOUS)', 'habitat' => 'Tropical.', 'notes' => 'n'
    )
    plant.reload
    expect(plant.safety_level).to eq('caution')
    expect(plant.safety_warning).to be(true)
    expect(plant.translations.dig(:en, :habitat)).to eq('Tropical.')
  end

  it 'clears the authority back to NULL with an empty string' do
    plant.update!(scientific_name_authority: 'L.')
    result = update(scientificNameAuthority: '')
    expect(result.dig('data', 'updatePlant', 'plant', 'scientificNameAuthority')).to be_nil
    expect(plant.reload.scientific_name_authority).to be_nil
  end

  it 'leaves the safety fields untouched when they are not sent' do
    plant.update!(safety_level: 'poisonous', edibility_uncertain: true)
    result = update(description: 'edited')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])
    expect(plant.reload.safety_level).to eq('poisonous')
    expect(plant.edibility_uncertain).to be(true)
  end
end
