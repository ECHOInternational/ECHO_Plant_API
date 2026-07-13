# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RestoreVariety Mutation', type: :graphql_mutation do
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: RestoreVarietyInput!) {
        restoreVariety(input: $input) {
          variety { id visibility publicationState accessLevel }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  def execute(variety, user)
    variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
    PlantApiSchema.execute(
      mutation,
      context: { current_user: user },
      variables: { input: { varietyId: variety_id } }
    )
  end

  context 'when anonymous' do
    it 'returns 401' do
      variety = create(:variety, :deleted, owned_by: 'a@b.com')
      result = execute(variety, nil)
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end
  end

  context 'when owner (readwrite user, legacy path)' do
    let(:user) { build(:user, :readwrite) }
    let(:variety) { create(:variety, :deleted, owned_by: user.email) }

    it 'restores the variety' do
      result = execute(variety, user)
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'restoreVariety', 'errors')).to be_empty
      variety.reload
      expect(variety.visibility).not_to eq 'deleted'
      expect(variety.deleted_at).to be_nil
    end

    context 'when variety was public before deletion' do
      let(:variety) do
        v = create(:variety, :public, owned_by: user.email)
        v.update(visibility: :deleted)
        v
      end

      it 'restores to public (preserved publication_state), not private' do
        result = execute(variety, user)
        expect(result['errors']).to be_nil
        variety.reload
        expect(variety.visibility).to eq 'public'
        expect(result.dig('data', 'restoreVariety', 'variety', 'visibility')).to eq 'PUBLIC'
      end
    end

    context 'when variety is not deleted' do
      let(:variety) { create(:variety, :private, owned_by: user.email) }

      it 'returns a 400 payload error' do
        result = execute(variety, user)
        errors = result.dig('data', 'restoreVariety', 'errors')
        expect(errors).not_to be_empty
        expect(errors.first['code']).to eq 400
        expect(errors.first['field']).to eq 'varietyId'
      end
    end
  end
end
