# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'updateFamily mutation', type: :request do
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }
  let(:global_id) { PlantApiSchema.id_from_object(family, Family, {}) }

  let(:query) do
    <<~GQL
      mutation($input: UpdateFamilyInput!) {
        updateFamily(input: $input) {
          family { name description seedBankingRank storagePhysiology seedLongevity }
          errors { field message code }
        }
      }
    GQL
  end

  def execute(user, input = {})
    PlantApiSchema.execute(
      query,
      variables: { 'input' => { 'familyId' => global_id }.merge(input) },
      context: { current_user: user }
    )
  end

  it 'rejects an anonymous caller with 401' do
    result = execute(nil, { 'description' => 'nope' })
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq(401)
  end

  it 'rejects a trust-2 writer with 403' do
    result = execute(build(:user, :readwrite), { 'description' => 'nope' })
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq(403)
  end

  it 'allows a trust-9 admin to edit the description' do
    result = execute(build(:user, :admin), { 'description' => 'Pea family' })
    expect(result['errors']).to be_nil
    expect(result.dig('data', 'updateFamily', 'family', 'description')).to eq('Pea family')
  end

  it 'writes the description into the requested locale' do
    execute(build(:user, :admin), { 'description' => 'Familia de las leguminosas', 'language' => 'es' })
    expect(family.reload.translations['es']['description']).to eq('Familia de las leguminosas')
  end

  it 'edits the seed banking metadata' do
    result = execute(build(:user, :admin),
                     { 'seedBankingRank' => 5, 'storagePhysiology' => 'orthodox',
                       'seedLongevity' => 'high' })
    data = result.dig('data', 'updateFamily', 'family')
    expect(data['seedBankingRank']).to eq(5)
    expect(data['storagePhysiology']).to eq('orthodox')
    expect(data['seedLongevity']).to eq('high')
  end

  it 'returns a payload error for an out-of-range rank' do
    result = execute(build(:user, :admin), { 'seedBankingRank' => 9 })
    expect(result.dig('data', 'updateFamily', 'errors', 0, 'code')).to eq(400)
    expect(family.reload.seed_banking_rank).to be_nil
  end

  it 'returns a payload error for an unknown storage physiology' do
    result = execute(build(:user, :admin), { 'storagePhysiology' => 'squishy' })
    expect(result.dig('data', 'updateFamily', 'errors', 0, 'code')).to eq(400)
  end

  # The list is immutable: identity is not editable at any trust level.
  it 'has no argument that could rename a family' do
    input_type = PlantApiSchema.types['UpdateFamilyInput']
    expect(input_type.arguments.keys).not_to include('name', 'colId', 'kingdom')
  end
end
