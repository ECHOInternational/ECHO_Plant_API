# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RestoreVarietyVersion Mutation', type: :graphql_mutation do
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: RestoreVarietyVersionInput!) {
        restoreVarietyVersion(input: $input) {
          variety { id hasEdibleMatureFruit }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  def entry_id(version)
    GraphQL::Schema::UniqueWithinType.encode('ChangeEntry', version.id)
  end

  def execute(variety, user, version_id)
    PlantApiSchema.execute(
      mutation,
      context: { current_user: user },
      variables: {
        input: {
          varietyId: PlantApiSchema.id_from_object(variety, Variety, {}),
          versionId: version_id
        }
      }
    )
  end

  def versions_for(variety)
    PaperTrail::Version.where(item_type: 'Variety', item_id: variety.id).order(:id)
  end

  describe 'authorization', versioning: true do
    let(:variety) { create(:variety, :public, has_edible_mature_fruit: false) }

    it 'returns 401 for anonymous callers' do
      variety.update!(has_edible_mature_fruit: true)
      result = execute(variety, nil, entry_id(versions_for(variety).first))

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end

    it 'returns 403 for a user who cannot edit' do
      variety.update!(has_edible_mature_fruit: true)
      result = execute(variety, build(:user, :readonly), entry_id(versions_for(variety).first))

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end

  describe 'restoring', versioning: true do
    let(:user) { build(:user, :readwrite) }
    let(:variety) do
      create(:variety, owned_by: user.email, created_by: user.email, has_edible_mature_fruit: false)
    end

    it 'restores the record and reports no errors' do
      create_version = versions_for(variety).first
      variety.update!(has_edible_mature_fruit: true)

      result = execute(variety, user, entry_id(create_version))
      payload = result.dig('data', 'restoreVarietyVersion')

      expect(result['errors']).to be_nil
      expect(payload['errors']).to be_empty
      expect(payload.dig('variety', 'hasEdibleMatureFruit')).to eq false
      expect(variety.reload.has_edible_mature_fruit).to eq false
    end

    it 'returns a payload error for the newest entry' do
      variety.update!(has_edible_mature_fruit: true)
      payload = execute(variety, user, entry_id(versions_for(variety).last))
                .dig('data', 'restoreVarietyVersion')

      expect(payload['errors'].first['code']).to eq 400
      expect(payload['errors'].first['field']).to eq 'versionId'
    end
  end
end
