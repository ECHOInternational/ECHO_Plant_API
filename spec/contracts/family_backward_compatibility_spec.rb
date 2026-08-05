# frozen_string_literal: true

require 'rails_helper'

# The brief requires demonstrating, not asserting, that existing queries return
# byte-identical results for every field other than the new ones.
RSpec.describe 'families changes nothing that already worked', type: :request do
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }

  # Exactly the field set the frozen mobile app requests in getPlantDetail.
  let(:mobile_query) do
    <<~GQL
      query($id: ID!) {
        plant(id: $id) {
          id primaryCommonName description scientificName familyNames
          createdBy createdAt updatedAt ownedBy
        }
      }
    GQL
  end

  def mobile_payload(plant)
    PlantApiSchema.execute(
      mobile_query,
      variables: { 'id' => PlantApiSchema.id_from_object(plant, Plant, {}) },
      context: { current_user: nil }
    ).to_h
  end

  it 'returns an identical payload whether or not a family is linked' do
    plant = create(:plant, :public, family_names: 'Leguminosae', family: nil)
    before = mobile_payload(plant)

    plant.update_columns(family_id: family.id)
    after = mobile_payload(plant.reload)

    expect(after).to eq(before)
  end

  it 'still returns the human-typed familyNames verbatim' do
    plant = create(:plant, :public, family_names: 'Cucurbitaceae – Gourd', family: family)
    payload = mobile_payload(plant)
    expect(payload.dig('data', 'plant', 'familyNames')).to eq('Cucurbitaceae – Gourd')
  end

  it 'keeps familyNames nullable and untyped as a plain String' do
    field = PlantApiSchema.types['Plant'].fields['familyNames']
    expect(field.type.to_type_signature).to eq('String')
    expect(field.deprecation_reason).to be_nil
  end
end
