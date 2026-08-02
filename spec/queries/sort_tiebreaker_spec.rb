# frozen_string_literal: true

require 'rails_helper'

# Every list query orders by a non-unique key (scientific name, name, created
# date), and the Relay connection paginates by OFFSET -- page two is a separate
# query with OFFSET n, not a continuation of page one. Postgres guarantees no
# particular order for rows that tie on the ORDER BY key, so without a
# deterministic final term the two queries can disagree about which tied row
# comes first, and a record is skipped or repeated across the boundary.
#
# Each spec edits one record between fetching page one and page two. That is not
# incidental: at test scale Postgres returns a small unindexed table in physical
# order and is accidentally stable, so specs without the edit pass with or
# without the fix and prove nothing. An UPDATE writes a new row version at the
# end of the heap and genuinely rearranges the scan -- which is also the real
# scenario, someone saving a record while a colleague pages through the list.
RSpec.describe 'List sort stability', type: :graphql_query do
  def page_ids(query_string, user, variables)
    result = PlantApiSchema.execute(query_string, context: { current_user: user }, variables: variables)
    expect(result['errors']).to be_nil
    result['data'].values.first['edges'].map { |e| e['node']['id'] }
  end

  describe 'plants ordered by a duplicated scientific name' do
    let(:query_string) do
      <<-GRAPHQL
      query($first: Int, $after: String, $sortDirection: SortDirection){
        plants(first: $first, after: $after, sortDirection: $sortDirection){
          totalCount
          edges { node { id } }
        }
      }
      GRAPHQL
    end

    it 'pages through every record exactly once when names tie and a row is edited mid-paging' do
      user = build(:user, :readwrite)
      # Every plant shares one scientific name, so the sort key can never decide
      # the order: only the tiebreaker can.
      created = Array.new(9) do
        create(:plant, scientific_name: 'Cucurbita moschata', visibility: :public, owned_by: user.email)
      end

      first_page = page_ids(query_string, user, { first: 3 })

      # Someone edits a record while you are paging. An UPDATE writes a new row
      # version at the end of the heap, so an unordered sequential scan returns
      # it in a different position than it did a moment ago. That is what turns
      # the missing tiebreaker from theoretical into a record you never see:
      # without one, this rearranges the very pages being walked.
      created.first.update!(family_names: 'Cucurbitaceae')

      second_page = page_ids(query_string, user, { first: 3, after: 'Mw' }) # offset 3
      third_page = page_ids(query_string, user, { first: 3, after: 'Ng' })  # offset 6

      seen = first_page + second_page + third_page
      expect(seen.uniq.size).to eq(9), "a record was skipped or repeated across pages: #{seen}"
      expect(seen.sort).to eq(created.map { |p| PlantApiSchema.id_from_object(p, Plant, {}) }.sort)
    end

    it 'is a total reversal when the direction flips' do
      user = build(:user, :readwrite)
      Array.new(5) do
        create(:plant, scientific_name: 'Amaranthus caudatus', visibility: :public, owned_by: user.email)
      end

      ascending = page_ids(query_string, user, { first: 5, sortDirection: 'ASC' })
      descending = page_ids(query_string, user, { first: 5, sortDirection: 'DESC' })

      # Without the tiebreaker applied in both directions these merely differ;
      # with it, one is exactly the other reversed.
      expect(descending).to eq(ascending.reverse)
    end
  end

  describe 'specimens ordered by an identical created date' do
    it 'pages through every record exactly once' do
      query_string = <<-GRAPHQL
      query($first: Int, $after: String){
        specimens(first: $first, after: $after){
          edges { node { id } }
        }
      }
      GRAPHQL

      user = build(:user, :readwrite)
      # created_at is the sort key, so make them collide exactly.
      stamp = Time.zone.parse('2026-01-01 12:00:00')
      created = Array.new(6) do
        create(:specimen, visibility: :public, owned_by: user.email, created_at: stamp, updated_at: stamp)
      end

      first_page = page_ids(query_string, user, { first: 3 })
      created.first.update!(notes: 'edited while paging')
      seen = first_page + page_ids(query_string, user, { first: 3, after: 'Mw' })

      expect(seen.uniq.size).to eq(6), "a record was skipped or repeated across pages: #{seen}"
      expect(seen.sort).to eq(created.map { |s| PlantApiSchema.id_from_object(s, Specimen, {}) }.sort)
    end
  end

  describe 'lookups ordered by a duplicated name' do
    it 'pages through every record exactly once' do
      query_string = <<-GRAPHQL
      query($first: Int, $after: String){
        tolerances(first: $first, after: $after){
          edges { node { id } }
        }
      }
      GRAPHQL

      user = build(:user, :readwrite)
      created = Array.new(6) { create(:tolerance, name: 'Drought') }

      first_page = page_ids(query_string, user, { first: 3 })
      created.first.touch
      seen = first_page + page_ids(query_string, user, { first: 3, after: 'Mw' })

      expect(seen.uniq.size).to eq(6), "a record was skipped or repeated across pages: #{seen}"
      expect(seen.sort).to eq(created.map { |t| PlantApiSchema.id_from_object(t, Tolerance, {}) }.sort)
    end
  end
end
