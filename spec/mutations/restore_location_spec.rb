# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RestoreLocation Mutation', type: :graphql_mutation do
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: RestoreLocationInput!) {
        restoreLocation(input: $input) {
          location { id visibility }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  def execute(location, user)
    location_id = PlantApiSchema.id_from_object(location, Location, {})
    PlantApiSchema.execute(
      mutation,
      context: { current_user: user },
      variables: { input: { locationId: location_id } }
    )
  end

  context 'when anonymous' do
    it 'returns 401' do
      location = create(:location, :deleted, owned_by: 'a@b.com')
      result = execute(location, nil)
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end
  end

  context 'when owner (readwrite user, legacy path)' do
    let(:user) { build(:user, :readwrite) }
    let(:location) { create(:location, :deleted, owned_by: user.email) }

    it 'restores the location' do
      result = execute(location, user)
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'restoreLocation', 'errors')).to be_empty
      location.reload
      expect(location.visibility).not_to eq 'deleted'
    end

    context 'when location is not deleted' do
      let(:location) { create(:location, owned_by: user.email) }

      it 'returns a 400 payload error' do
        result = execute(location, user)
        errors = result.dig('data', 'restoreLocation', 'errors')
        expect(errors).not_to be_empty
        expect(errors.first['code']).to eq 400
        expect(errors.first['field']).to eq 'locationId'
      end
    end
  end
end
