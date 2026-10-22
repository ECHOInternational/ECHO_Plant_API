# frozen_string_literal: true

require 'rails_helper'

# FPI plan API-8, API-9 and API-10: the fields ECHOcommunity's projection
# reads (its contract probe checks each of them).
RSpec.describe 'EC projection fields', type: :graphql_query do
  before { Mobility.locale = nil }

  def gid(record, type = record.class)
    PlantApiSchema.id_from_object(record, type, {})
  end

  def run(query, user: nil, **vars)
    result = PlantApiSchema.execute(query, variables: vars, context: { current_user: user })
    expect(result['errors']).to be_nil
    result['data']
  end

  describe 'Organization.uuid' do
    it 'is the organization primary key (the IdP UUID for a real organization)' do
      org = create(:organization, :real)
      plant = create(:plant, :public, owner_organization_id: org.id, source_organization_id: org.id)
      data = run('query($id: ID!) { plant(id: $id) { ownerOrganization { uuid } sourceOrganization { uuid } } }',
                 id: gid(plant))
      expect(data.dig('plant', 'ownerOrganization', 'uuid')).to eq org.id
      expect(data.dig('plant', 'sourceOrganization', 'uuid')).to eq org.id
    end
  end

  describe 'Plant.commonNames' do
    let(:plant) { create(:plant, :public) }
    let(:query) do
      <<~GRAPHQL
        query($id: ID!, $language: String, $first: Int) {
          plant(id: $id) {
            commonNames(language: $language, first: $first) {
              totalCount pageInfo { hasNextPage } nodes { name language primary }
            }
          }
        }
      GRAPHQL
    end

    before do
      create(:common_name, plant: plant, name: 'Zeta', language: 'EN')
      create(:common_name, plant: plant, name: 'Alpha', language: 'EN')
      create(:common_name, plant: plant, name: 'Primary', language: 'EN', primary: true)
      create(:common_name, plant: plant, name: 'Beta', language: 'en')
      create(:common_name, plant: plant, name: 'Aardvark', language: 'UND')
    end

    def names(**vars)
      run(query, id: gid(plant), **vars).dig('plant', 'commonNames')
    end

    it 'orders primary first, then by name, and counts every name' do
      conn = names
      expect(conn['totalCount']).to eq 5
      expect(conn['nodes'].pluck('name')).to eq %w[Primary Aardvark Alpha Beta Zeta]
    end

    it 'filters by language case-insensitively, including a lower-case stored row' do
      conn = names(language: 'en')
      expect(conn['totalCount']).to eq 4
      expect(conn['nodes'].pluck('name')).to eq %w[Primary Alpha Beta Zeta]
      expect(names(language: 'UND')['nodes'].pluck('name')).to eq %w[Aardvark]
    end

    it 'keeps totalCount across pages and reports hasNextPage' do
      conn = names(language: 'EN', first: 2)
      expect(conn['totalCount']).to eq 4
      expect(conn['pageInfo']['hasNextPage']).to be true
      expect(conn['nodes'].pluck('name')).to eq %w[Primary Alpha]
    end

    it 'keeps the GraphQL connection type name for existing documents' do
      type = PlantApiSchema.types['Plant'].fields['commonNames'].type.unwrap
      expect(type.graphql_name).to eq 'CommonNameConnection'
    end
  end

  describe 'plants(updatedSince:)' do
    let(:since) { 1.hour.ago.change(usec: 0) }
    let(:query) { 'query($since: ISO8601DateTime) { plants(updatedSince: $since) { totalCount nodes { uuid } } }' }

    def old_plant(**attrs)
      plant = create(:plant, :public, **attrs)
      plant.update_columns(updated_at: since - 1.day)
      plant
    end

    def uuids(since_value = since.iso8601)
      run(query, since: since_value).dig('plants', 'nodes').pluck('uuid')
    end

    it 'returns plants whose own row changed at or after the time' do
      fresh = create(:plant, :public)
      fresh.update_columns(updated_at: since)
      old = old_plant
      expect(uuids).to contain_exactly(fresh.id)
      expect(uuids(nil)).to include(fresh.id, old.id)
    end

    it 'returns a plant whose common name changed, through the versions root stamp', versioning: true do
      plant = old_plant
      PaperTrail.request(controller_info: { metadata: { origin: 'spec' } }) do
        create(:common_name, plant: plant, name: 'New name')
      end
      plant.update_columns(updated_at: since - 1.day)
      expect(uuids).to contain_exactly(plant.id)
    end

    it 'returns every plant of a data source whose publication rule changed' do
      source = create(:data_source)
      plant = old_plant(data_source_id: source.id)
      other = old_plant
      source.update_columns(updated_at: since - 2.days)
      expect(uuids).to be_empty

      source.update!(publication_rule: { 'version' => 1, 'locale' => 'en', 'text_fields' => ['description'],
                                         'min_text_chars' => 10, 'image_suffices' => true })
      expect(uuids).to contain_exactly(plant.id)
      expect(uuids).not_to include(other.id)
    end
  end

  describe 'Plant.meetsQualityBar' do
    it 'follows the data source rule and is true for ECHO plants, reading the rules once' do
      source = create(:data_source, publication_rule: { 'version' => 1, 'locale' => 'en',
                                                        'text_fields' => %w[description uses cultivation],
                                                        'min_text_chars' => 500, 'image_suffices' => true })
      short = create(:plant, :public, scientific_name: 'A short', data_source_id: source.id)
      short.update_columns(translations: { 'en' => { 'description' => 'x' * 499 } })
      long = create(:plant, :public, scientific_name: 'B long', data_source_id: source.id)
      long.update_columns(translations: { 'en' => { 'description' => 'x' * 500 } })
      echo = create(:plant, :public, scientific_name: 'C echo')

      rule_reads = 0
      counter = ->(*, payload) { rule_reads += 1 if payload[:sql].include?('FROM "data_sources"') }
      data = ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        run('{ plants(first: 10) { nodes { uuid meetsQualityBar } } }')
      end

      flags = data.dig('plants', 'nodes').to_h { |n| [n['uuid'], n['meetsQualityBar']] }
      expect(flags).to eq(short.id => false, long.id => true, echo.id => true)
      expect(rule_reads).to eq 1
    end
  end
end
