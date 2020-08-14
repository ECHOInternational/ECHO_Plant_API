# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GrowthHabit Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'loads growthhabits by ID' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			growthHabit(id: $id){
				id
				name
			}
		}
    GRAPHQL

    growth_habit = create(:growth_habit, name: 'loaded by id')
    growth_habit_id = PlantApiSchema.id_from_object(growth_habit, GrowthHabit, {})
    result = PlantApiSchema.execute(query_string, variables: { id: growth_habit_id })
    growth_habit_result = result['data']['growthHabit']
    # Make sure the query worked
    expect(growth_habit_result['id']).to eq growth_habit_id
    expect(growth_habit_result['name']).to eq 'loaded by id'
  end

  it 'falls back to a language when the one requested is not available' do
    query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			growthHabit(id: $id, language: $language){
				id
				name
			}
		}
    GRAPHQL

    growth_habit = create(:growth_habit, name: 'name in english')
    growth_habit.name_es = 'name in spanish'
    growth_habit.save

    growth_habit_id = PlantApiSchema.id_from_object(growth_habit, GrowthHabit, {})
    result_en = PlantApiSchema.execute(query_string, variables: { id: growth_habit_id, language: 'en' })
    result_fr = PlantApiSchema.execute(query_string, variables: { id: growth_habit_id, language: 'fr' })
    growth_habit_result_en = result_en['data']['growthHabit']
    growth_habit_result_fr = result_fr['data']['growthHabit']
    # Make sure the query worked
    expect(growth_habit_result_en['id']).to eq growth_habit_id
    expect(growth_habit_result_en['name']).to eq 'name in english'
    expect(growth_habit_result_fr['id']).to eq growth_habit_id
    expect(growth_habit_result_fr['name']).to eq 'name in english'
  end

  describe 'translations attribute' do
    it 'returns a list of languages when requested' do
      query_string = <<-GRAPHQL
			query($id: ID!){
				growthHabit(id: $id){
					id
					name
					translations{
						locale
						name
					}
				}
			}
      GRAPHQL

      growth_habit = create(:growth_habit, name: 'nameen')
      growth_habit.name_es = 'namees'
      growth_habit.save

      growth_habit_id = PlantApiSchema.id_from_object(growth_habit, GrowthHabit, {})
      result = PlantApiSchema.execute(query_string, variables: { id: growth_habit_id })
      growth_habit_result = result['data']['growthHabit']

      expect(growth_habit_result['id']).to eq growth_habit_id
      expect(growth_habit_result['translations']).to be_kind_of Array
      expect(growth_habit_result['translations'].length).to eq 2

      result_en = growth_habit_result['translations'].detect { |l| l['locale'] == 'en' }
      result_es = growth_habit_result['translations'].detect { |l| l['locale'] == 'es' }

      expect(result_en['name']).to eq 'nameen'
      expect(result_es['name']).to eq 'namees'
    end
  end
end
