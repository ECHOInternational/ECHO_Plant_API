# frozen_string_literal: true

require 'rails_helper'

# Regression spec for the production crash:
# "Cannot return null for non-nullable field Location.irrigated"
#
# Root cause: 7 legacy rows had NULL irrigated; the GraphQL field is Boolean!.
# Fix: migration backfills NULLs -> false, adds DEFAULT false, adds NOT NULL.
#
# These examples pin all three layers of the fix.
RSpec.describe 'Location.irrigated NOT NULL constraint', type: :model do
  # 1. DB-level NOT NULL: attempting to persist irrigated: nil should fail.
  it 'raises a DB-level NOT NULL violation when irrigated is set to nil explicitly' do
    location = build(:location, irrigated: nil)
    # AR lets the in-memory object past model validations (no presence validation),
    # but the DB constraint must reject it.
    expect { location.save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  # 2. Column DEFAULT: creating a location via the GraphQL createLocation mutation
  #    without specifying irrigated yields false (column default).
  it 'defaults irrigated to false when the mutation omits the irrigated argument' do
    current_user = build(:user, :superadmin)

    query = <<~GRAPHQL
      mutation($input: CreateLocationInput!) {
        createLocation(input: $input) {
          location { id irrigated }
          errors { field message code }
        }
      }
    GRAPHQL

    result = PlantApiSchema.execute(
      query,
      context: { current_user: current_user },
      variables: {
        input: {
          name: 'Default irrigated test',
          soilQuality: 'FAIR'
        }
      }
    )

    expect(result['errors']).to be_nil
    payload = result.dig('data', 'createLocation')
    expect(payload['errors']).to be_empty
    expect(payload['location']['irrigated']).to eq false
  end

  # 3. GraphQL resolver: querying irrigated returns a non-null Boolean (the crash is gone).
  it 'resolves irrigated as a non-null Boolean in a GraphQL location query' do
    location = create(:location, :public, irrigated: true)
    location_id = PlantApiSchema.id_from_object(location, Location, {})

    query = <<~GRAPHQL
      query($id: ID!) {
        location(id: $id) {
          id
          irrigated
        }
      }
    GRAPHQL

    result = PlantApiSchema.execute(query, variables: { id: location_id })

    expect(result['errors']).to be_nil
    expect(result.dig('data', 'location', 'irrigated')).to eq true
  end
end
