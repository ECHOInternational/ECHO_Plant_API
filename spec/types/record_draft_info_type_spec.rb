# frozen_string_literal: true

require 'rails_helper'

# RecordDraftInfoType#author/#last_editor fall back to the principal's email
# when display_name is nil. Most real principals today have no display_name:
# Principal.resolve! (called from application_controller.rb#resolve_actor) is
# never passed one, so the un-fallback'd field rendered "Unknown" for the
# common case.
RSpec.describe 'RecordDraftInfoType author/lastEditor display_name fallback', type: :graphql_query do
  let(:user) { build(:user, :superadmin) }
  let(:plant) { create(:plant, scientific_name: 'Live name') }
  let(:query) do
    <<~GRAPHQL
      query($id: ID!) {
        plant(id: $id) {
          draft { author lastEditor }
        }
      }
    GRAPHQL
  end

  def run
    vars = { id: PlantApiSchema.id_from_object(plant, Plant, {}) }
    PlantApiSchema.execute(query, context: { current_user: user }, variables: vars)
                  .dig('data', 'plant', 'draft')
  end

  it 'uses display_name when present' do
    principal = create(:principal, display_name: 'Jo Author', email: 'jo@example.com')
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft name' },
                          author_principal_id: principal.id, last_editor_principal_id: principal.id)

    draft = run
    expect(draft['author']).to eq 'Jo Author'
    expect(draft['lastEditor']).to eq 'Jo Author'
  end

  it 'falls back to email when display_name is nil (the resolve_actor shape)' do
    principal = create(:principal, display_name: nil, email: 'no-name@example.com')
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft name' },
                          author_principal_id: principal.id, last_editor_principal_id: principal.id)

    draft = run
    expect(draft['author']).to eq 'no-name@example.com'
    expect(draft['lastEditor']).to eq 'no-name@example.com'
  end

  it 'falls back to email when display_name is an empty string' do
    principal = create(:principal, display_name: '', email: 'blank-name@example.com')
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft name' },
                          author_principal_id: principal.id, last_editor_principal_id: principal.id)

    draft = run
    expect(draft['author']).to eq 'blank-name@example.com'
    expect(draft['lastEditor']).to eq 'blank-name@example.com'
  end
end
