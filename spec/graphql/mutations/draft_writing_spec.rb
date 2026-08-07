# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'updatePlant saveAsDraft' do
  let(:user) { build(:user, :superadmin) }
  let(:plant) { create(:plant, scientific_name: 'Live name') }
  let(:global_id) { PlantApiSchema.id_from_object(plant, Plant, {}) }
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: UpdatePlantInput!) {
        updatePlant(input: $input) {
          plant { id scientificName }
          errors { code field message }
        }
      }
    GRAPHQL
  end

  def execute(input)
    PlantApiSchema.execute(mutation, context: { current_user: user },
                                     variables: { input: input })
  end

  it 'leaves the live row untouched' do
    execute({ plantId: global_id, scientificName: 'Draft name', saveAsDraft: true })
    expect(plant.reload.scientific_name).to eq('Live name')
  end

  it 'stores the change in a draft' do
    execute({ plantId: global_id, scientificName: 'Draft name', saveAsDraft: true })
    expect(plant.reload.record_draft.data).to include('scientific_name' => 'Draft name')
  end

  it 'writes no PaperTrail version for the plant' do
    expect {
      execute({ plantId: global_id, scientificName: 'Draft name', saveAsDraft: true })
    }.not_to(change { plant.versions.count })
  end

  it 'still writes live when saveAsDraft is absent, so mobile is unaffected' do
    execute({ plantId: global_id, scientificName: 'Direct name' })
    expect(plant.reload.scientific_name).to eq('Direct name')
    expect(plant.record_draft).to be_nil
  end

  it 'merges successive draft saves rather than replacing them' do
    execute({ plantId: global_id, scientificName: 'First', saveAsDraft: true })
    execute({ plantId: global_id, familyNames: 'Testaceae', saveAsDraft: true })
    data = plant.reload.record_draft.data
    expect(data).to include('scientific_name' => 'First', 'family_names' => 'Testaceae')
  end

  it 'does not advance base_updated_at on a later save' do
    execute({ plantId: global_id, scientificName: 'First', saveAsDraft: true })
    original = plant.reload.record_draft.base_updated_at
    execute({ plantId: global_id, scientificName: 'Second', saveAsDraft: true })
    expect(plant.reload.record_draft.base_updated_at).to eq(original)
  end

  it 'stages a translatable field under translations, keyed by locale' do
    execute({ plantId: global_id, description: 'Draft description', language: 'en', saveAsDraft: true })
    data = plant.reload.record_draft.data
    expect(data.dig('translations', 'en', 'description')).to eq('Draft description')
    expect(data).not_to have_key('description')
  end

  # family_id arrives via the loads: family_id argument as a loaded Family
  # record (or explicit nil) under :family, never as a literal family_id
  # string, so it needs its own explicit staging path -- see
  # DraftWriting#stage_family_id.
  describe 'staging familyId' do
    let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }

    it 'stages the family id and leaves the live row untouched' do
      family_gid = PlantApiSchema.id_from_object(family, Family, {})
      execute({ plantId: global_id, familyId: family_gid, saveAsDraft: true })
      expect(plant.reload.record_draft.data).to include('family_id' => family.id)
      expect(plant.reload.family_id).to be_nil
    end

    it 'stages an explicit clear as family_id => nil, leaving the live family intact' do
      plant.update!(family: family)
      execute({ plantId: global_id, familyId: nil, saveAsDraft: true })
      expect(plant.reload.record_draft.data).to include('family_id' => nil)
      expect(plant.reload.family_id).to eq(family.id)
    end
  end
end
