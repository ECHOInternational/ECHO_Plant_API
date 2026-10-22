# frozen_string_literal: true

require 'rails_helper'

# API-21: anonymous query-cost limits.
#
# Three limits, all reachable without a token:
#   - plants connections (root, Category.plants, Family.plants) reject an
#     explicit first:/last: above 500 with a coded error (code 400);
#   - PlantApiSchema.max_depth;
#   - PlantApiSchema.max_complexity.
#
# The schema limits are sized from the real documents of every client, so no
# existing client query is rejected:
#   - the frozen mobile app: the heredocs of spec/contracts/mobile_*_spec.rb,
#     which hold its documents verbatim (interpolated ids replaced below);
#   - the admin SPA: spec/fixtures/client_documents/admin_spa/, every operation
#     extracted verbatim from plant_data_admin_interface
#     src/lib/api/__generated__/gql.ts, measured with $first/$last = 200 (the
#     largest page size the SPA sends);
#   - ECHOcommunity: spec/fixtures/client_documents/echocommunity/, every
#     Plant API document of app/services/plant_api/** and the GMCC selection
#     tool, rendered from their Ruby constants, measured with $first = 25
#     (PlantApi::Client::PAGE_SIZE); plus ecd5_snapshot_planned.graphql, the
#     planned snapshot walk (FPI plan ECD-5) at $first = 100.
# When a client adds or changes a document, refresh its copy there.
#
# Measured 2026-10-22 (complexity / depth, introspection not counted):
#   mobile        68 documents  max 58,801 / 7   (unpaginated specimens sync)
#   admin SPA    135 documents  max 16,437 / 9   (SpecimenDetail)
#   ECHOcommunity  8 documents  max 15,130 / 6   (projection_common_names)
#   ECD-5 planned               286,406 / 7
#   abusive families(first: 100) { plants(first: 100) { images commonNames } }
#                               1,280,202 / 7
# Limits: max_complexity 400,000 (ECD-5 plus 40 percent; the abusive query is
# 3.2x over), max_depth 12 (deepest real document plus 3).
RSpec.describe 'Query cost limits', type: :graphql_query do
  def self.fixtures
    Rails.root.join('spec/fixtures/client_documents')
  end

  def measure(document, variables = {})
    query = GraphQL::Query.new(PlantApiSchema, document, variables: variables, context: { current_user: nil })
    complexity, depth = GraphQL::Analysis.analyze_query(
      query, [GraphQL::Analysis::QueryComplexity, GraphQL::Analysis::QueryDepth]
    )
    raise complexity if complexity.is_a?(StandardError)
    raise depth if depth.is_a?(StandardError)

    { complexity: complexity, depth: depth }
  end

  def page_variables(document, size)
    document.scan(/\$(first|last)\s*:\s*Int/).flatten.uniq.to_h { |name| [name, size] }
  end

  def self.mobile_documents
    Rails.root.glob('spec/contracts/mobile_*_spec.rb').sort.flat_map do |file|
      File.read(file).scan(/<<[~-]GRAPHQL\n(.*?)\n\s*GRAPHQL/m).each_with_index.map do |(body), index|
        ["#{file.basename}##{index}", body.gsub(/#\{[^}]*\}/, 'UGxhbnQtMDAwMA==')]
      end
    end
  end

  def self.fixture_documents(client)
    fixtures.join(client).glob('*.graphql').sort.map { |file| [file.basename.to_s, file.read] }
  end

  def expect_within_limits(cost)
    expect(cost[:complexity]).to be <= PlantApiSchema.max_complexity
    expect(cost[:depth]).to be <= PlantApiSchema.max_depth
  end

  def execute(document, variables: {}, user: nil)
    PlantApiSchema.execute(document, variables: variables, context: { current_user: user })
  end

  it 'sets the schema limits recorded above, not counting introspection' do
    expect(PlantApiSchema.max_complexity).to eq(400_000)
    expect(PlantApiSchema.max_depth).to eq(12)
    expect(PlantApiSchema.max_complexity_count_introspection_fields).to be(false)
    expect(PlantApiSchema.count_introspection_fields).to be(false)
  end

  describe 'every real client document fits' do
    it 'finds the documents' do
      expect(self.class.mobile_documents.size).to be >= 60
      expect(self.class.fixture_documents('admin_spa').size).to be >= 130
      expect(self.class.fixture_documents('echocommunity').size).to be >= 8
    end

    mobile_documents.each do |name, document|
      it "mobile #{name}" do
        expect_within_limits(measure(document, page_variables(document, 15)))
      end
    end

    fixture_documents('admin_spa').each do |name, document|
      it "admin SPA #{name}" do
        expect_within_limits(measure(document, page_variables(document, 200)))
      end
    end

    fixture_documents('echocommunity').each do |name, document|
      it "ECHOcommunity #{name}" do
        size = name.start_with?('ecd5') ? 100 : 25
        expect_within_limits(measure(document, page_variables(document, size)))
      end
    end

    it 'admits the planned ECD-5 snapshot walk at first: 100 with headroom' do
      document = self.class.fixtures.join('echocommunity/ecd5_snapshot_planned.graphql').read
      result = execute(document, variables: { 'first' => 100 })
      expect(result['errors']).to be_nil
      expect(measure(document, 'first' => 100)[:complexity]).to be < PlantApiSchema.max_complexity * 0.75
    end

    it 'admits the full introspection query (SPA codegen)' do
      result = execute(GraphQL::Introspection::INTROSPECTION_QUERY)
      expect(result['errors']).to be_nil
    end
  end

  describe 'rejections' do
    it 'rejects a deep nested families { plants { images commonNames } } over the complexity limit' do
      document = <<~GRAPHQL
        {
          families(first: 100) { nodes { plants(first: 100) { nodes {
            id images { nodes { id baseUrl } } commonNames { nodes { name } }
          } } } }
        }
      GRAPHQL
      result = execute(document)
      expect(result['data']).to be_nil
      expect(result['errors'].first['message']).to match(/exceeds max complexity of 400000/)
    end

    it 'rejects a query nested deeper than max_depth' do
      document = <<~GRAPHQL
        {
          plants(first: 1) { nodes { categories(first: 1) { nodes { plants(first: 1) { nodes {
            categories(first: 1) { nodes { plants(first: 1) { nodes { categories(first: 1) { nodes { id } } } } } }
          } } } } } }
        }
      GRAPHQL
      result = execute(document)
      expect(result['data']).to be_nil
      expect(result['errors'].first['message']).to match(/exceeds max depth of 12/)
    end
  end

  describe 'plants page size' do
    let(:category) { create(:category, :public) }
    let(:family) { Family.importing { create(:family) } }

    def page_error(result)
      result['errors']&.find { |e| e.dig('extensions', 'code') == 400 }
    end

    it 'rejects plants(first: 501) with code 400' do
      result = execute('{ plants(first: 501) { nodes { id } } }')
      expect(page_error(result)['message']).to match(/first: 501 exceeds the maximum page size of 500/)
      expect(result.dig('data', 'plants')).to be_nil
    end

    it 'rejects plants(last: 501) with code 400' do
      result = execute('query($l: Int) { plants(last: $l) { nodes { id } } }', variables: { 'l' => 501 })
      expect(page_error(result)['message']).to match(/last: 501/)
    end

    it 'accepts plants(first: 500)' do
      create(:plant, :public)
      result = execute('{ plants(first: 500) { totalCount nodes { id } } }')
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'plants', 'totalCount')).to eq(1)
    end

    it 'rejects Category.plants(first: 501) with code 400' do
      id = PlantApiSchema.id_from_object(category, Category, {})
      result = execute('query($id: ID!) { category(id: $id) { plants(first: 501) { nodes { id } } } }',
                       variables: { 'id' => id })
      expect(page_error(result)).to be_present
    end

    it 'rejects Family.plants(first: 501) with code 400' do
      family
      result = execute('{ families(first: 1) { nodes { plants(first: 501) { nodes { id } } } } }')
      expect(page_error(result)).to be_present
    end

    it 'leaves the unpaginated mobile call alone (governed by the full-sync guard)' do
      result = execute('{ plants(language: "en") { nodes { id } } }')
      expect(result['errors']).to be_nil
    end
  end
end
