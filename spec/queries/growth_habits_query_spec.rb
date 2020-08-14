# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'growthHabits Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'returns a list of growth habits' do
    query_string = <<-GRAPHQL
		query{
			growthHabits{
				nodes {
					id
					name
				}
			}
		}
    GRAPHQL

    growth_habit_a = create(:growth_habit, name: 'growth_habit a')
    growth_habit_b = create(:growth_habit, name: 'growth_habit b')

    growth_habit_a_id = PlantApiSchema.id_from_object(growth_habit_a, GrowthHabit, {})
    growth_habit_b_id = PlantApiSchema.id_from_object(growth_habit_b, GrowthHabit, {})

    result = PlantApiSchema.execute(query_string)
    growth_habit_result = result['data']['growthHabits']['nodes']

    result_a = growth_habit_result.detect { |c| c['id'] == growth_habit_a_id }
    result_b = growth_habit_result.detect { |c| c['id'] == growth_habit_b_id }
    expect(result_a['id']).to eq growth_habit_a_id
    expect(result_b['id']).to eq growth_habit_b_id
  end

  describe 'name filter' do
    before :each do
      @current_user = build(:user, :admin)

      @query_string = <<-GRAPHQL
				query($name: String){
					growthHabits(name: $name){
						nodes{
							id
							name
						}
					}
				}
      GRAPHQL

      create(:growth_habit,  name: 'Happy Man')
      create(:growth_habit,  name: 'Sad Girl')
      create(:growth_habit,  name: 'Mad Girl')
      create(:growth_habit,  name: 'Happy Girl')
      create(:growth_habit,  name: 'Orange Boy')
    end

    it 'does not limit when nil' do
      result = PlantApiSchema.execute(@query_string, variables: { name: nil })
      growth_habit_result = result['data']['growthHabits']['nodes']

      expect(growth_habit_result.length).to eq 5
    end

    it 'can return single results' do
      result = PlantApiSchema.execute(@query_string, variables: { name: 'orange' })
      growth_habit_result = result['data']['growthHabits']['nodes']
      expect(growth_habit_result.length).to eq 1
    end

    it 'can return multiple results' do
      result = PlantApiSchema.execute(@query_string, variables: { name: 'girl' })
      growth_habit_result = result['data']['growthHabits']['nodes']

      expect(growth_habit_result.length).to eq 3
    end
  end

  it 'returns growth habits in the specified language with fallbacks' do
    query_string = <<-GRAPHQL
		query($language: String){
			growthHabits(language: $language){
				nodes {
					id
					name
				}
			}
		}
    GRAPHQL

    growth_habit_a = create(:growth_habit, name: 'growth_habit a name en')
    growth_habit_b = create(:growth_habit, name: 'growth_habit b name en')
    growth_habit_b.name_es = 'growth_habit b name es'
    growth_habit_b.save

    growth_habit_a_id = PlantApiSchema.id_from_object(growth_habit_a, GrowthHabit, {})
    growth_habit_b_id = PlantApiSchema.id_from_object(growth_habit_b, GrowthHabit, {})

    # result = PlantApiSchema.execute(query_string)
    result_en = PlantApiSchema.execute(query_string, variables: { language: 'en' })
    result_es = PlantApiSchema.execute(query_string, variables: { language: 'es' })

    growth_habit_result_en = result_en['data']['growthHabits']['nodes']
    growth_habit_result_es = result_es['data']['growthHabits']['nodes']

    result_en_a = growth_habit_result_en.detect { |c| c['id'] == growth_habit_a_id }
    result_en_b = growth_habit_result_en.detect { |c| c['id'] == growth_habit_b_id }

    result_es_a = growth_habit_result_es.detect { |c| c['id'] == growth_habit_a_id }
    result_es_b = growth_habit_result_es.detect { |c| c['id'] == growth_habit_b_id }

    expect(result_en_a['name']).to eq 'growth_habit a name en'
    expect(result_en_b['name']).to eq 'growth_habit b name en'

    expect(result_es_a['name']).to eq 'growth_habit a name en'
    expect(result_es_b['name']).to eq 'growth_habit b name es'
  end

  describe 'totalCount attribute' do
    it 'counts all available records' do
      query_string = <<-GRAPHQL
			query{
				growthHabits{
					totalCount
				}
			}
      GRAPHQL

      create(:growth_habit, name: 'growth_habit a')
      create(:growth_habit, name: 'growth_habit b')

      result = PlantApiSchema.execute(query_string)
      total_count = result['data']['growthHabits']['totalCount']

      expect(total_count).to eq 2
    end
  end
end
