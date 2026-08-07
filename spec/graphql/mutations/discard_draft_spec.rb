# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'discardDraft' do
  let(:user) { build(:user, :superadmin) }
  let(:plant) { create(:plant, scientific_name: 'Live', visibility: :public) }
  let(:plant_gid) { PlantApiSchema.id_from_object(plant, Plant, {}) }

  let(:mutation) do
    <<~GRAPHQL
      mutation($input: DiscardDraftInput!) {
        discardDraft(input: $input) {
          record { ... on Plant { id scientificName } }
          errors { code field message }
        }
      }
    GRAPHQL
  end

  def discard(id: plant_gid, as: user)
    PlantApiSchema.execute(mutation, context: { current_user: as },
                                     variables: { input: { recordId: id } })
  end

  it 'destroys the draft' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Abandoned' },
                          base_updated_at: plant.updated_at)
    discard
    expect(plant.reload.record_draft).to be_nil
  end

  it 'leaves the live record untouched' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Abandoned' },
                          base_updated_at: plant.updated_at)
    discard
    expect(plant.reload.scientific_name).to eq('Live')
  end

  it 'returns the record and no errors' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Abandoned' },
                          base_updated_at: plant.updated_at)
    result = discard
    expect(result.dig('data', 'discardDraft', 'record', 'scientificName')).to eq('Live')
    expect(result.dig('data', 'discardDraft', 'errors')).to be_empty
  end

  it 'is a no-op when there is no draft' do
    result = discard
    expect(result.dig('data', 'discardDraft', 'errors')).to be_empty
    expect(result['errors']).to be_nil
  end

  it 'refuses a reader with a 403 and keeps the draft' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Abandoned' },
                          base_updated_at: plant.updated_at)
    result = discard(as: build(:user, :readonly))
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq(403)
    expect(plant.reload.record_draft).to be_present
  end
end
