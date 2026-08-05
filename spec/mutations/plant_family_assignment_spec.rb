# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'assigning a family to a plant', type: :request do
  let(:user) { build(:user, :readwrite) }
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }
  let(:family_gid) { PlantApiSchema.id_from_object(family, Family, {}) }

  let(:query) do
    <<~GQL
      mutation($input: UpdatePlantInput!) {
        updatePlant(input: $input) {
          plant { familyNames family { name } }
          errors { field message code }
        }
      }
    GQL
  end

  def update(plant, input)
    PlantApiSchema.execute(
      query,
      variables: { 'input' => {
        'plantId' => PlantApiSchema.id_from_object(plant, Plant, {})
      }.merge(input) },
      context: { current_user: user }
    )
  end

  it 'links the family' do
    plant = create(:plant, owned_by: user.email, family_names: nil)
    result = update(plant, { 'familyId' => family_gid })
    expect(result.dig('data', 'updatePlant', 'plant', 'family', 'name')).to eq('Fabaceae')
  end

  it 'mirrors the family name into a BLANK familyNames' do
    plant = create(:plant, owned_by: user.email, family_names: nil)
    update(plant, { 'familyId' => family_gid })
    expect(plant.reload.family_names).to eq('Fabaceae')
  end

  it 'mirrors into an empty-string familyNames' do
    plant = create(:plant, owned_by: user.email, family_names: '   ')
    update(plant, { 'familyId' => family_gid })
    expect(plant.reload.family_names).to eq('Fabaceae')
  end

  # The single most important guarantee in this task: a human typed that text.
  it 'NEVER overwrites a populated familyNames' do
    plant = create(:plant, owned_by: user.email, family_names: 'Leguminosae - Pea')
    update(plant, { 'familyId' => family_gid })
    expect(plant.reload.family_names).to eq('Leguminosae - Pea')
  end

  it 'leaves familyNames writable on its own, with no family set' do
    plant = create(:plant, owned_by: user.email, family_names: 'Whatever the user typed')
    update(plant, { 'familyNames' => 'Still free text' })
    expect(plant.reload.family_names).to eq('Still free text')
    expect(plant.reload.family_id).to be_nil
  end
end
