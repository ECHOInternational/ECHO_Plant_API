# frozen_string_literal: true

require 'rails_helper'

# S7 puts NOT NULL on created_by_principal_id, owner_organization_id and
# source_organization_id. Nothing may write NULL into them before then.
#
# The path that could is ApplicationController#resolve_actor, which degrades to
# legacy authorization on a database error rather than returning 500 -- leaving
# principal and personal_organization nil while the request proceeds. A create
# in that state used to succeed and insert an unattributable row that nothing
# would ever repair.
RSpec.describe 'Creating without a resolved identity', type: :graphql_query do
  let(:query_string) do
    <<-GRAPHQL
      mutation($input: CreatePlantInput!){
        createPlant(input: $input){
          plant { id ownerOrganization { id } }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  def create_plant(user)
    PlantApiSchema.execute(
      query_string,
      context: { current_user: user },
      variables: { input: { primaryCommonName: 'Unattributable', language: 'en' } }
    )
  end

  it 'refuses the write and says so, rather than inserting NULL ownership' do
    user = build(:user, :readwrite, :unresolved)

    expect { @result = create_plant(user) }.not_to change(Plant, :count)

    expect(@result['errors']).to be_nil, "query error: #{@result['errors'].inspect}"
    payload = @result['data']['createPlant']
    expect(payload['plant']).to be_nil
    expect(payload['errors'].first['code']).to eq 503
    expect(payload['errors'].first['message']).to match(/could not resolve/i)
  end

  it 'stamps ownership normally once the identity resolves' do
    user = build(:user, :readwrite)

    expect { @result = create_plant(user) }.to change(Plant, :count).by(1)

    payload = @result['data']['createPlant']
    expect(payload['errors']).to be_empty
    expect(payload['plant']['ownerOrganization']).not_to be_nil

    plant = Plant.find_by(id: Plant.last.id)
    expect(plant.owner_organization_id).not_to be_nil
    expect(plant.source_organization_id).not_to be_nil
    expect(plant.created_by_principal_id).not_to be_nil
  end

  # The same guarantee has to hold for every create that stamps ownership, or
  # S7's NOT NULL lands on a table another mutation can still violate. Each one
  # needs its own required inputs, so the shapes are spelled out rather than
  # shared.
  it 'createCategory also refuses an unattributable write' do
    expect(unattributable_codes('createCategory', 'CreateCategoryInput',
                                { name: 'Unattributable', language: 'en' })).to include(503)
  end

  it 'createLocation also refuses an unattributable write' do
    expect(unattributable_codes('createLocation', 'CreateLocationInput',
                                { name: 'Unattributable', soilQuality: 'GOOD' })).to include(503)
  end

  it 'createSpecimen also refuses an unattributable write' do
    plant = create(:plant)
    plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
    expect(unattributable_codes('createSpecimen', 'CreateSpecimenInput',
                                { name: 'Unattributable', plantId: plant_id })).to include(503)
  end

  def unattributable_codes(field, input_type, input)
    user = build(:user, :superadmin, :unresolved)
    mutation = <<-GRAPHQL
      mutation($input: #{input_type}!){
        #{field}(input: $input){ errors { field message code } }
      }
    GRAPHQL

    result = PlantApiSchema.execute(mutation, context: { current_user: user },
                                              variables: { input: input })
    expect(result['errors']).to be_nil, "query error: #{result['errors'].inspect}"
    result['data'][field]['errors'].map { |e| e['code'] }
  end
end
