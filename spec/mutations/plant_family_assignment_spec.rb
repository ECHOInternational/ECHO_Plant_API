# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'assigning a family to a plant', type: :request do
  let(:user) { build(:user, :readwrite) }
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }
  let(:family_gid) { PlantApiSchema.id_from_object(family, Family, {}) }

  let(:update_query) do
    <<~GQL
      mutation($input: UpdatePlantInput!) {
        updatePlant(input: $input) {
          plant { familyNames family { name } }
          errors { field message code }
        }
      }
    GQL
  end

  let(:create_query) do
    <<~GQL
      mutation($input: CreatePlantInput!) {
        createPlant(input: $input) {
          plant { familyNames family { name } }
          errors { field message code }
        }
      }
    GQL
  end

  def update(plant, input)
    PlantApiSchema.execute(
      update_query,
      variables: { 'input' => {
        'plantId' => PlantApiSchema.id_from_object(plant, Plant, {})
      }.merge(input) },
      context: { current_user: user }
    )
  end

  def create_plant(input)
    PlantApiSchema.execute(
      create_query,
      variables: { 'input' => { 'primaryCommonName' => 'Test Plant' }.merge(input) },
      context: { current_user: user }
    )
  end

  describe 'updatePlant' do
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

    it 'clearing the family via familyId: null does not clobber a blank familyNames as a side effect' do
      plant = create(:plant, owned_by: user.email, family_names: '   ', family: family)
      update(plant, { 'familyId' => nil })
      expect(plant.reload.family_id).to be_nil
      expect(plant.reload.family_names).to eq('   ')
    end

    describe 'a combined familyId + familyNames submit (the admin SPA dirty-value save shape)' do
      it 'mirrors when the SAME call supplies a whitespace-only familyNames, matching createPlant' do
        plant = create(:plant, owned_by: user.email, family_names: nil)
        update(plant, { 'familyId' => family_gid, 'familyNames' => '   ' })
        expect(plant.reload.family_names).to eq('Fabaceae')
      end

      it 'mirrors when the SAME call explicitly nulls out a previously populated familyNames, matching createPlant' do
        plant = create(:plant, owned_by: user.email, family_names: 'Some Existing Text')
        update(plant, { 'familyId' => family_gid, 'familyNames' => nil })
        expect(plant.reload.family_names).to eq('Fabaceae')
      end

      it 'never overwrites when the SAME call supplies a populated familyNames, matching createPlant' do
        plant = create(:plant, owned_by: user.email, family_names: 'Old Text')
        update(plant, { 'familyId' => family_gid, 'familyNames' => 'Fresh Text' })
        expect(plant.reload.family_names).to eq('Fresh Text')
      end
    end
  end

  describe 'createPlant' do
    it 'links the family' do
      result = create_plant({ 'familyId' => family_gid })
      expect(result.dig('data', 'createPlant', 'plant', 'family', 'name')).to eq('Fabaceae')
    end

    it 'mirrors the family name into a blank familyNames' do
      result = create_plant({ 'familyId' => family_gid })
      expect(result.dig('data', 'createPlant', 'plant', 'familyNames')).to eq('Fabaceae')
    end

    it 'mirrors into a whitespace-only familyNames' do
      result = create_plant({ 'familyId' => family_gid, 'familyNames' => '   ' })
      expect(result.dig('data', 'createPlant', 'plant', 'familyNames')).to eq('Fabaceae')
    end

    # The single most important guarantee in this task: a human typed that text.
    it 'NEVER overwrites a populated familyNames' do
      result = create_plant({ 'familyId' => family_gid, 'familyNames' => 'Leguminosae - Pea' })
      expect(result.dig('data', 'createPlant', 'plant', 'familyNames')).to eq('Leguminosae - Pea')
    end

    it 'leaves familyNames writable on its own, with no family set' do
      result = create_plant({ 'familyNames' => 'Still free text' })
      expect(result.dig('data', 'createPlant', 'plant', 'familyNames')).to eq('Still free text')
      expect(result.dig('data', 'createPlant', 'plant', 'family')).to be_nil
    end
  end
end
