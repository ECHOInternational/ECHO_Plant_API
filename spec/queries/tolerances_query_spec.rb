# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tolerances Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'returns a list of image attributes' do
    query_string = <<-GRAPHQL
		query{
			tolerances{
				nodes {
					id
					name
				}
			}
		}
    GRAPHQL

    tolerance_a = create(:tolerance, name: 'tolerance a')
    tolerance_b = create(:tolerance, name: 'tolerance b')

    tolerance_a_id = PlantApiSchema.id_from_object(tolerance_a, Tolerance, {})
    tolerance_b_id = PlantApiSchema.id_from_object(tolerance_b, Tolerance, {})

    result = PlantApiSchema.execute(query_string)
    tolerance_result = result['data']['tolerances']['nodes']

    result_a = tolerance_result.detect { |c| c['id'] == tolerance_a_id }
    result_b = tolerance_result.detect { |c| c['id'] == tolerance_b_id }

    expect(result_a['id']).to eq tolerance_a_id
    expect(result_b['id']).to eq tolerance_b_id
  end

  describe 'name filter' do
    before :each do
      @current_user = build(:user, :admin)

      @query_string = <<-GRAPHQL
				query($name: String){
					tolerances(name: $name){
						nodes{
							id
							name
						}
					}
				}
      GRAPHQL

      create(:tolerance,  name: 'Happy Man')
      create(:tolerance,  name: 'Sad Girl')
      create(:tolerance,  name: 'Mad Girl')
      create(:tolerance,  name: 'Happy Girl')
      create(:tolerance,  name: 'Orange Boy')
    end

    it 'does not limit when nil' do
      result = PlantApiSchema.execute(@query_string, variables: { name: nil })
      tolerance_result = result['data']['tolerances']['nodes']

      expect(tolerance_result.length).to eq 5
    end

    it 'can return single results' do
      result = PlantApiSchema.execute(@query_string, variables: { name: 'orange' })
      tolerance_result = result['data']['tolerances']['nodes']
      expect(tolerance_result.length).to eq 1
    end

    it 'can return multiple results' do
      result = PlantApiSchema.execute(@query_string, variables: { name: 'girl' })
      tolerance_result = result['data']['tolerances']['nodes']

      expect(tolerance_result.length).to eq 3
    end
  end

  it 'returns tolerances in the specified language with fallbacks' do
    query_string = <<-GRAPHQL
		query($language: String){
			tolerances(language: $language){
				nodes {
					id
					name
				}
			}
		}
    GRAPHQL

    tolerance_a = create(:tolerance, name: 'tolerance a name en')
    tolerance_b = create(:tolerance, name: 'tolerance b name en')
    tolerance_b.name_es = 'tolerance b name es'
    tolerance_b.save

    tolerance_a_id = PlantApiSchema.id_from_object(tolerance_a, Tolerance, {})
    tolerance_b_id = PlantApiSchema.id_from_object(tolerance_b, Tolerance, {})

    # result = PlantApiSchema.execute(query_string)
    result_en = PlantApiSchema.execute(query_string, variables: { language: 'en' })
    result_es = PlantApiSchema.execute(query_string, variables: { language: 'es' })

    tolerance_result_en = result_en['data']['tolerances']['nodes']
    tolerance_result_es = result_es['data']['tolerances']['nodes']

    result_en_a = tolerance_result_en.detect { |c| c['id'] == tolerance_a_id }
    result_en_b = tolerance_result_en.detect { |c| c['id'] == tolerance_b_id }

    result_es_a = tolerance_result_es.detect { |c| c['id'] == tolerance_a_id }
    result_es_b = tolerance_result_es.detect { |c| c['id'] == tolerance_b_id }

    expect(result_en_a['name']).to eq 'tolerance a name en'
    expect(result_en_b['name']).to eq 'tolerance b name en'

    expect(result_es_a['name']).to eq 'tolerance a name en'
    expect(result_es_b['name']).to eq 'tolerance b name es'
  end

  describe 'totalCount attribute' do
    it 'counts all available records' do
      query_string = <<-GRAPHQL
			query{
				tolerances{
					totalCount
				}
			}
      GRAPHQL

      create(:tolerance, name: 'tolerance a')
      create(:tolerance, name: 'tolerance b')

      result = PlantApiSchema.execute(query_string)
      total_count = result['data']['tolerances']['totalCount']

      expect(total_count).to eq 2
    end
  end
end
