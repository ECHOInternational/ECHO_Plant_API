# frozen_string_literal: true

require 'rails_helper'

# GraphQL surface of the safety concept: the fields on PlantType, the
# translation type, and the two resolver filters (schema-delta items 5, 17).
RSpec.describe 'plants safety fields and filters', type: :graphql_query do
  let!(:safe) { create(:plant, :public, scientific_name: 'Musa acuminata', scientific_name_authority: 'Colla') }
  let!(:cautioned) do
    create(:plant, :public, scientific_name: 'Abrus precatorius', safety_level: 'caution', safety_note_en: 'Caution',
                            edibility_uncertain: true, habitat_en: 'Tropical.', notes_en: 'n')
  end
  let!(:poisonous) { create(:plant, :public, scientific_name: 'Amanita phalloides', safety_level: 'poisonous') }

  def execute(query, **variables)
    PlantApiSchema.execute(query, context: { current_user: nil }, variables: variables)
  end

  it 'exposes the level, the derived warning, the flag, the authority and the translations' do
    query = <<~GRAPHQL
      query($id: ID!) {
        plant(id: $id) {
          scientificName scientificNameAuthority safetyLevel safetyWarning edibilityUncertain
          safetyNote habitat notes
          translations { locale safetyNote habitat notes }
        }
      }
    GRAPHQL
    result = execute(query, id: PlantApiSchema.id_from_object(cautioned, Plant, {}))
    expect(result['errors']).to be_nil
    plant = result.dig('data', 'plant')
    expect(plant).to include(
      'scientificName' => 'Abrus precatorius', 'scientificNameAuthority' => nil,
      'safetyLevel' => 'CAUTION', 'safetyWarning' => true, 'edibilityUncertain' => true,
      'safetyNote' => 'Caution', 'habitat' => 'Tropical.', 'notes' => 'n'
    )
    expect(plant['translations']).to include('locale' => 'en', 'safetyNote' => 'Caution', 'habitat' => 'Tropical.', 'notes' => 'n')

    result = execute(query, id: PlantApiSchema.id_from_object(safe, Plant, {}))
    expect(result.dig('data', 'plant')).to include(
      'scientificNameAuthority' => 'Colla', 'safetyLevel' => 'NONE', 'safetyWarning' => false,
      'edibilityUncertain' => false, 'safetyNote' => nil
    )
  end

  describe 'filters' do
    let(:query) do
      <<~GRAPHQL
        query($level: SafetyLevel, $warning: Boolean) {
          plants(safetyLevel: $level, hasSafetyWarning: $warning, visibility: PUBLIC) {
            nodes { scientificName }
          }
        }
      GRAPHQL
    end

    def names(result)
      expect(result['errors']).to be_nil
      result.dig('data', 'plants', 'nodes').map { |n| n['scientificName'] }.sort
    end

    it 'returns everything when neither filter is given or both are explicit nulls' do
      expect(names(execute(query))).to eq(['Abrus precatorius', 'Amanita phalloides', 'Musa acuminata'])
      expect(names(execute(query, level: nil, warning: nil))).to eq(['Abrus precatorius', 'Amanita phalloides', 'Musa acuminata'])
    end

    it 'matches an exact level' do
      expect(names(execute(query, level: 'POISONOUS'))).to eq(['Amanita phalloides'])
      expect(names(execute(query, level: 'NONE'))).to eq(['Musa acuminata'])
    end

    it 'splits on the presence of any warning' do
      expect(names(execute(query, warning: true))).to eq(['Abrus precatorius', 'Amanita phalloides'])
      expect(names(execute(query, warning: false))).to eq(['Musa acuminata'])
    end
  end
end
