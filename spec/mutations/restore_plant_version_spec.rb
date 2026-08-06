# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RestorePlantVersion Mutation', type: :graphql_mutation do
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: RestorePlantVersionInput!) {
        restorePlantVersion(input: $input) {
          plant { id scientificName }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  def entry_id(version)
    GraphQL::Schema::UniqueWithinType.encode('ChangeEntry', version.id)
  end

  def execute(plant, user, version_id)
    PlantApiSchema.execute(
      mutation,
      context: { current_user: user },
      variables: {
        input: {
          plantId: PlantApiSchema.id_from_object(plant, Plant, {}),
          versionId: version_id
        }
      }
    )
  end

  def versions_for(plant)
    PaperTrail::Version.where(item_type: 'Plant', item_id: plant.id).order(:id)
  end

  describe 'authorization', versioning: true do
    let(:plant) { create(:plant, :public, scientific_name: 'Original') }

    it 'returns 401 for anonymous callers' do
      plant.update!(scientific_name: 'Second')
      result = execute(plant, nil, entry_id(versions_for(plant).first))

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end

    it 'returns 403 for a user who cannot edit' do
      plant.update!(scientific_name: 'Second')
      result = execute(plant, build(:user, :readonly), entry_id(versions_for(plant).first))

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end

  describe 'restoring', versioning: true do
    let(:user) { build(:user, :readwrite) }
    let(:plant) do
      create(:plant, owned_by: user.email, created_by: user.email, scientific_name: 'Original')
    end

    it 'restores the record and reports no errors' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')

      result = execute(plant, user, entry_id(create_version))
      payload = result.dig('data', 'restorePlantVersion')

      expect(result['errors']).to be_nil
      expect(payload['errors']).to be_empty
      expect(payload.dig('plant', 'scientificName')).to eq 'Original'
      expect(plant.reload.scientific_name).to eq 'Original'
    end

    it 'returns a payload error for the newest entry' do
      plant.update!(scientific_name: 'Second')
      payload = execute(plant, user, entry_id(versions_for(plant).last)).dig('data', 'restorePlantVersion')

      expect(payload['errors'].first['code']).to eq 400
      expect(payload['errors'].first['field']).to eq 'versionId'
    end

    it 'returns a payload error for a malformed entry id' do
      payload = execute(plant, user, 'not-a-global-id').dig('data', 'restorePlantVersion')

      expect(payload['errors'].first['code']).to eq 404
      expect(payload['errors'].first['field']).to eq 'versionId'
    end

    it 'returns a payload error for a global id of the wrong type' do
      wrong = PlantApiSchema.id_from_object(plant, Plant, {})
      payload = execute(plant, user, wrong).dig('data', 'restorePlantVersion')

      expect(payload['errors'].first['code']).to eq 404
    end
  end
end
