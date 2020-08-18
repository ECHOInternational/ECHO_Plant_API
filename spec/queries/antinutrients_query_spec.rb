# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Antinutrients Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'returns a list of image attributes' do
    query_string = <<-GRAPHQL
		query{
			antinutrients{
				nodes {
					id
					name
				}
			}
		}
    GRAPHQL

    antinutrient_a = create(:antinutrient, name: 'antinutrient a')
    antinutrient_b = create(:antinutrient, name: 'antinutrient b')

    antinutrient_a_id = PlantApiSchema.id_from_object(antinutrient_a, Antinutrient, {})
    antinutrient_b_id = PlantApiSchema.id_from_object(antinutrient_b, Antinutrient, {})

    result = PlantApiSchema.execute(query_string)
    antinutrient_result = result['data']['antinutrients']['nodes']

    result_a = antinutrient_result.detect { |c| c['id'] == antinutrient_a_id }
    result_b = antinutrient_result.detect { |c| c['id'] == antinutrient_b_id }

    expect(result_a['id']).to eq antinutrient_a_id
    expect(result_b['id']).to eq antinutrient_b_id
  end

  describe 'name filter' do
    before :each do
      @current_user = build(:user, :admin)

      @query_string = <<-GRAPHQL
				query($name: String){
					antinutrients(name: $name){
						nodes{
							id
							name
						}
					}
				}
      GRAPHQL

      create(:antinutrient,  name: 'Happy Man')
      create(:antinutrient,  name: 'Sad Girl')
      create(:antinutrient,  name: 'Mad Girl')
      create(:antinutrient,  name: 'Happy Girl')
      create(:antinutrient,  name: 'Orange Boy')
    end

    it 'does not limit when nil' do
      result = PlantApiSchema.execute(@query_string, variables: { name: nil })
      antinutrient_result = result['data']['antinutrients']['nodes']

      expect(antinutrient_result.length).to eq 5
    end

    it 'can return single results' do
      result = PlantApiSchema.execute(@query_string, variables: { name: 'orange' })
      antinutrient_result = result['data']['antinutrients']['nodes']
      expect(antinutrient_result.length).to eq 1
    end

    it 'can return multiple results' do
      result = PlantApiSchema.execute(@query_string, variables: { name: 'girl' })
      antinutrient_result = result['data']['antinutrients']['nodes']

      expect(antinutrient_result.length).to eq 3
    end
  end

  it 'returns antinutrients in the specified language with fallbacks' do
    query_string = <<-GRAPHQL
		query($language: String){
			antinutrients(language: $language){
				nodes {
					id
					name
				}
			}
		}
    GRAPHQL

    antinutrient_a = create(:antinutrient, name: 'antinutrient a name en')
    antinutrient_b = create(:antinutrient, name: 'antinutrient b name en')
    antinutrient_b.name_es = 'antinutrient b name es'
    antinutrient_b.save

    antinutrient_a_id = PlantApiSchema.id_from_object(antinutrient_a, Antinutrient, {})
    antinutrient_b_id = PlantApiSchema.id_from_object(antinutrient_b, Antinutrient, {})

    # result = PlantApiSchema.execute(query_string)
    result_en = PlantApiSchema.execute(query_string, variables: { language: 'en' })
    result_es = PlantApiSchema.execute(query_string, variables: { language: 'es' })

    antinutrient_result_en = result_en['data']['antinutrients']['nodes']
    antinutrient_result_es = result_es['data']['antinutrients']['nodes']

    result_en_a = antinutrient_result_en.detect { |c| c['id'] == antinutrient_a_id }
    result_en_b = antinutrient_result_en.detect { |c| c['id'] == antinutrient_b_id }

    result_es_a = antinutrient_result_es.detect { |c| c['id'] == antinutrient_a_id }
    result_es_b = antinutrient_result_es.detect { |c| c['id'] == antinutrient_b_id }

    expect(result_en_a['name']).to eq 'antinutrient a name en'
    expect(result_en_b['name']).to eq 'antinutrient b name en'

    expect(result_es_a['name']).to eq 'antinutrient a name en'
    expect(result_es_b['name']).to eq 'antinutrient b name es'
  end

  describe 'totalCount attribute' do
    it 'counts all available records' do
      query_string = <<-GRAPHQL
			query{
				antinutrients{
					totalCount
				}
			}
      GRAPHQL

      create(:antinutrient, name: 'antinutrient a')
      create(:antinutrient, name: 'antinutrient b')

      result = PlantApiSchema.execute(query_string)
      total_count = result['data']['antinutrients']['totalCount']

      expect(total_count).to eq 2
    end
  end
end
