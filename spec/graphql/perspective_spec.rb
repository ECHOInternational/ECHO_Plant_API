# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'perspective lens' do
  let(:plant) { create(:plant, scientific_name: 'Live name', visibility: :public) }
  let!(:draft) do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft name' })
  end
  let(:query) do
    <<~GRAPHQL
      query($id: ID!, $perspective: Perspective) {
        plant(id: $id, perspective: $perspective) { scientificName }
      }
    GRAPHQL
  end

  def run(user, perspective = nil)
    vars = { id: PlantApiSchema.id_from_object(plant, Plant, {}) }
    vars[:perspective] = perspective if perspective
    PlantApiSchema.execute(query, context: { current_user: user }, variables: vars)
                  .dig('data', 'plant', 'scientificName')
  end

  it 'defaults to published content' do
    expect(run(build(:user, :superadmin))).to eq('Live name')
  end

  it 'returns staged content under DRAFT for a user who may edit' do
    expect(run(build(:user, :superadmin), 'DRAFT')).to eq('Draft name')
  end

  # The leak-prevention property. An anonymous caller cannot name the argument
  # into existence, and even naming it must not yield draft content.
  it 'never returns draft content to an anonymous caller' do
    expect(run(nil)).to eq('Live name')
    expect(run(nil, 'DRAFT')).to eq('Live name')
  end

  it 'never returns draft content to a read-only user' do
    expect(run(build(:user, :readonly), 'DRAFT')).to eq('Live name')
  end

  describe 'the draft metadata field' do
    let(:query_with_draft_field) do
      <<~GRAPHQL
        query($id: ID!) {
          plant(id: $id) {
            scientificName
            draft {
              updatedAt
              author
              lastEditor
              changedFields
              isStale
            }
          }
        }
      GRAPHQL
    end

    def run_draft_field(user)
      vars = { id: PlantApiSchema.id_from_object(plant, Plant, {}) }
      PlantApiSchema.execute(query_with_draft_field, context: { current_user: user }, variables: vars)
    end

    it 'is visible to a user who may edit the record' do
      result = run_draft_field(build(:user, :superadmin))
      draft_data = result.dig('data', 'plant', 'draft')

      expect(draft_data).not_to be_nil
      expect(draft_data['changedFields']).to eq(['scientific_name'])
      expect(draft_data['author']).to eq(draft.author.display_name)
      expect(draft_data['lastEditor']).to eq(draft.last_editor.display_name)
    end

    it 'is null for a user who may not edit the record' do
      result = run_draft_field(build(:user, :readonly))

      expect(result.dig('data', 'plant', 'draft')).to be_nil
    end

    it 'is null for an anonymous caller' do
      result = run_draft_field(nil)

      expect(result.dig('data', 'plant', 'draft')).to be_nil
    end

    it 'is null when there is no draft' do
      other_plant = create(:plant, scientific_name: 'No draft here', visibility: :public)
      vars = { id: PlantApiSchema.id_from_object(other_plant, Plant, {}) }
      result = PlantApiSchema.execute(query_with_draft_field, context: { current_user: build(:user, :superadmin) },
                                                              variables: vars)

      expect(result.dig('data', 'plant', 'draft')).to be_nil
    end
  end

  describe 'draft field on list queries does not N+1' do
    it 'issues a bounded number of record_drafts queries for a 20-row list' do
      user = build(:user, :superadmin)
      plants = create_list(:plant, 20, visibility: :public)
      plants.each { |p| create(:record_draft, draftable: p, data: { 'scientific_name' => 'x' }) }

      list_query = <<~GRAPHQL
        query {
          plants(first: 20) {
            edges { node { scientificName draft { changedFields } } }
          }
        }
      GRAPHQL

      record_draft_query_count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql].to_s
        record_draft_query_count += 1 if sql.include?('record_drafts')
      end

      result = nil
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        result = PlantApiSchema.execute(list_query, context: { current_user: user })
      end

      expect(result['errors']).to be_nil
      edges = result.dig('data', 'plants', 'edges')
      expect(edges.length).to eq(20)
      expect(edges.map { |e| e['node']['draft']['changedFields'] }).to all(eq(['scientific_name']))
      # One preload query for the whole page, not one per row.
      expect(record_draft_query_count).to be <= 2
    end
  end
end
