# frozen_string_literal: true

require 'rails_helper'

# Reads of the 7 range fields now go through RangeLiteral.serialize
# (app/graphql/types/concerns/range_literal_fields.rb), so what a mutation
# accepts is what a subsequent query returns -- previously reads fell back to
# graphql-ruby's default String coercion, i.e. Ruby's Range#to_s
# ("5.5..7.0", "0...Infinity"), which the admin SPA's range parser cannot
# read back into its inputs.
RSpec.describe 'range literal read/write symmetry', type: :graphql_mutation do
  before :each do
    Mobility.locale = nil
  end

  let(:current_user) { build(:user, :readwrite) }
  let!(:plant) { create(:plant, owned_by: current_user.email, created_by: current_user.email) }
  let(:plant_gid) { PlantApiSchema.id_from_object(plant, Plant, {}) }

  def update(input)
    query = <<~GRAPHQL
      mutation($input: UpdatePlantInput!) {
        updatePlant(input: $input) {
          errors { field message code }
          plant { uuid }
        }
      }
    GRAPHQL
    PlantApiSchema.execute(query, context: { current_user: current_user },
                                  variables: { input: { plantId: plant_gid }.merge(input) })
  end

  def read(perspective: 'PUBLISHED')
    query = <<~GRAPHQL
      query($id: ID!, $perspective: Perspective) {
        plant(id: $id, perspective: $perspective) {
          nAccumulationRange
          phRange
        }
      }
    GRAPHQL
    PlantApiSchema.execute(query, context: { current_user: current_user },
                                  variables: { id: plant_gid, perspective: perspective })
                  .dig('data', 'plant')
  end

  it 'round-trips an unbounded-upper integer literal' do
    result = update(nAccumulationRange: '[10,]')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])

    expect(read['nAccumulationRange']).to eq '[10,]'
  end

  it 'round-trips an unbounded-lower integer literal' do
    result = update(nAccumulationRange: '[,10]')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])

    expect(read['nAccumulationRange']).to eq '[,10]'
  end

  it 'round-trips a fully unbounded integer literal' do
    result = update(nAccumulationRange: '[,]')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])

    expect(read['nAccumulationRange']).to eq '[,]'
  end

  it 'round-trips an unbounded-lower numrange literal' do
    result = update(phRange: '[,10]')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])

    expect(read['phRange']).to eq '[,10]'
  end

  it 'round-trips a fully unbounded numrange literal' do
    result = update(phRange: '[,]')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])

    expect(read['phRange']).to eq '[,]'
  end

  it 'round-trips a finite exclusive-upper numrange literal (raw-data shape)' do
    result = update(phRange: '[1,2)')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])

    expect(read['phRange']).to eq '[1,2)'
  end

  it 'rejects an open-lower-bound literal as a clean payload error instead of ' \
     'raising a cast error (Ruby Range cannot represent an exclusive lower bound)' do
    original_ph_range = read['phRange']

    result = update(phRange: '(5,10]')
    errors = result.dig('data', 'updatePlant', 'errors')

    expect(errors).to eq(
      [{ 'field' => 'phRange',
         'message' => 'phRange is not a valid range literal (expected e.g. "[0,10]")',
         'code' => 400 }]
    )
    # The value is untouched -- the mutation short-circuited before any save,
    # rather than raising an ArgumentError mid-save.
    expect(read['phRange']).to eq original_ph_range
  end

  it 'round-trips a finite inclusive integer literal, decrementing back from ' \
     "Postgres's canonicalized exclusive-upper storage" do
    result = update(nAccumulationRange: '[500,2000]')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])

    # Confirms the canonicalization this spec exists to guard against: what
    # is actually stored is the exclusive-upper form, not what was typed.
    expect(plant.reload.n_accumulation_range).to eq(500...2001)
    expect(read['nAccumulationRange']).to eq '[500,2000]'
  end

  it 'round-trips a numrange literal per the documented BigDecimal formatting choice ' \
     '(trailing .0 stripped)' do
    result = update(phRange: '[5.5,7.0]')
    expect(result.dig('data', 'updatePlant', 'errors')).to eq([])

    expect(read['phRange']).to eq '[5.5,7]'
  end

  describe 'DRAFT perspective' do
    it 'returns the bracket literal for a staged (never-persisted-to-Postgres) range value' do
      result = update(nAccumulationRange: '[500,2000]', saveAsDraft: true)
      expect(result.dig('data', 'updatePlant', 'errors')).to eq([])

      # The live row is untouched; only the draft carries the staged value.
      expect(plant.reload.n_accumulation_range).not_to eq(500...2001)

      expect(read(perspective: 'DRAFT')['nAccumulationRange']).to eq '[500,2000]'
    end
  end

  describe 'VarietyType' do
    let!(:variety) { create(:variety, owned_by: current_user.email, created_by: current_user.email) }
    let(:variety_gid) { PlantApiSchema.id_from_object(variety, Variety, {}) }

    it 'serializes range fields the same way as PlantType' do
      mutation = <<~GRAPHQL
        mutation($input: UpdateVarietyInput!) {
          updateVariety(input: $input) {
            errors { field message code }
            variety { uuid }
          }
        }
      GRAPHQL
      result = PlantApiSchema.execute(mutation, context: { current_user: current_user },
                                                variables: { input: { varietyId: variety_gid,
                                                                      optimalAltitudeRange: '[500,2000]' } })
      expect(result.dig('data', 'updateVariety', 'errors')).to eq([])

      query = <<~GRAPHQL
        query($id: ID!) {
          variety(id: $id) { optimalAltitudeRange }
        }
      GRAPHQL
      result = PlantApiSchema.execute(query, context: { current_user: current_user },
                                             variables: { id: variety_gid })
      expect(result.dig('data', 'variety', 'optimalAltitudeRange')).to eq '[500,2000]'
    end
  end
end
