# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life cycle event node lookup', type: :graphql_query do
  let(:current_user) { build(:user, :readwrite) }
  let!(:specimen) { create(:specimen, :public) }
  let!(:event) { create(:harvest_event, specimen: specimen) }
  let(:event_gid) { PlantApiSchema.id_from_object(event, event.class, {}) }

  it 'resolves an event through the node field' do
    query = <<-GRAPHQL
      query($id: ID!) {
        node(id: $id) {
          id
          ... on HarvestEvent { uuid quantity }
        }
      }
    GRAPHQL
    result = PlantApiSchema.execute(query, context: { current_user: current_user }, variables: { id: event_gid })
    expect(result['errors']).to be_nil
    expect(result['data']['node']['uuid']).to eq event.id
  end
end
