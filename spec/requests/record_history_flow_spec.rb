# frozen_string_literal: true

require 'rails_helper'

# The whole feature end to end at the schema boundary: edit a plant, read the
# history it produced, restore an earlier entry, and see the restore recorded.
RSpec.describe 'Record history end to end', type: :request do
  let(:user) { build(:user, :readwrite) }
  let(:plant) do
    create(:plant, owned_by: user.email, created_by: user.email, scientific_name: 'Original Name')
  end

  let(:history_query) do
    <<~GRAPHQL
      query($id: ID!) {
        plant(id: $id) {
          recordHistory(first: 10) {
            totalCount
            edges { node { id event origin actorLabel subjectType restorable changes { field before after } } }
          }
        }
      }
    GRAPHQL
  end

  let(:restore_mutation) do
    <<~GRAPHQL
      mutation($input: RestorePlantVersionInput!) {
        restorePlantVersion(input: $input) {
          plant { scientificName }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  def plant_global_id
    PlantApiSchema.id_from_object(plant, Plant, {})
  end

  def history_nodes
    PlantApiSchema
      .execute(history_query, context: { current_user: user }, variables: { id: plant_global_id })
      .dig('data', 'plant', 'recordHistory', 'edges')
      .map { |edge| edge['node'] }
  end

  it 'shows the edit, restores it, and records the restore', versioning: true do
    PaperTrail.request(
      whodunnit: user.principal.id,
      controller_info: { metadata: { origin: 'api', principal_id: user.principal.id } }
    ) do
      plant.update!(scientific_name: 'Edited Name')
    end

    nodes = history_nodes
    expect(nodes.first['event']).to eq 'UPDATED'
    # The :user factory resolves a principal without a display name.
    expect(nodes.first['actorLabel']).to eq user.email
    expect(nodes.first['changes']).to include(
      'field' => 'scientificName', 'before' => 'Original Name', 'after' => 'Edited Name'
    )

    restorable = nodes.find { |node| node['restorable'] }
    expect(restorable['event']).to eq 'CREATED'

    payload = PlantApiSchema.execute(
      restore_mutation,
      context: { current_user: user },
      variables: { input: { plantId: plant_global_id, versionId: restorable['id'] } }
    ).dig('data', 'restorePlantVersion')

    expect(payload['errors']).to be_empty
    expect(payload.dig('plant', 'scientificName')).to eq 'Original Name'
    expect(plant.reload.scientific_name).to eq 'Original Name'

    after_restore = history_nodes
    expect(after_restore.first['event']).to eq 'RESTORED'
    expect(after_restore.first['subjectType']).to eq 'RECORD'
    expect(after_restore.first['changes']).to include(
      'field' => 'scientificName', 'before' => 'Edited Name', 'after' => 'Original Name'
    )
  end
end
