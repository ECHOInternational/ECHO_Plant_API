# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Variety Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'loads varieties by ID' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			variety(id: $id){
				id
        name
        createdAt
        updatedAt
			}
		}
    GRAPHQL

    variety = create(:variety, :public, name: 'loaded by id')
    variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
    result = PlantApiSchema.execute(query_string, variables: { id: variety_id })

    variety_result = result['data']['variety']
    # Make sure the query worked
    expect(variety_result['id']).to eq variety_id
    expect(variety_result['name']).to eq 'loaded by id'
  end

  it 'does not load varieties for which the user is not authorized' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			variety(id: $id){
				id
        name
        createdAt
        updatedAt
			}
		}
    GRAPHQL

    variety = create(:variety, :private, name: 'Private Variety')
    variety_id = PlantApiSchema.id_from_object(variety, Variety, {})

    result = PlantApiSchema.execute(query_string, variables: { id: variety_id })
    expect(result['data']['variety']).to be nil
    expect(result['errors'].count).to eq 1
    expect(result['errors'][0]['extensions']['code']).to eq 404
  end

  context 'when user is authenticated' do
    it 'loads owned records' do
      current_user = build(:user)

      query_string = <<-GRAPHQL
			query($id: ID!){
				variety(id: $id){
					id
          name
          createdAt
          updatedAt
					ownedBy
				}
			}
      GRAPHQL

      variety = create(:variety, :private, name: 'Private Variety', owned_by: current_user.email)
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})

      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: variety_id })

      variety_result = result['data']['variety']
      # Make sure the query worked
      expect(variety_result['id']).to eq variety_id
      expect(variety_result['name']).to eq 'Private Variety'
      expect(variety_result['ownedBy']).to eq current_user.email
    end
  end

  context 'when user is admin' do
    it 'loads unowned records' do
      current_user = build(:user, :admin)

      query_string = <<-GRAPHQL
			query($id: ID!){
				variety(id: $id){
					id
          name
          createdAt
          updatedAt
					ownedBy
				}
			}
      GRAPHQL

      variety = create(:variety, :private, name: 'Private Variety', owned_by: 'nottheadmin')
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})

      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: variety_id })

      variety_result = result['data']['variety']
      # Make sure the query worked
      expect(variety_result['id']).to eq variety_id
      expect(variety_result['name']).to eq 'Private Variety'
      expect(variety_result['ownedBy']).to eq 'nottheadmin'
    end
  end

  it 'loads varieties in the specified language' do
    query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			variety(id: $id, language: $language){
				id
        name
        createdAt
        updatedAt
			}
		}
    GRAPHQL

    variety = create(:variety, :public, name: 'name in english')
    variety.name_es = 'name in spanish'
    variety.save

    variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
    result_en = PlantApiSchema.execute(query_string, variables: { id: variety_id, language: 'en' })
    result_es = PlantApiSchema.execute(query_string, variables: { id: variety_id, language: 'es' })

    variety_result_en = result_en['data']['variety']
    variety_result_es = result_es['data']['variety']
    # Make sure the query worked
    expect(variety_result_en['id']).to eq variety_id
    expect(variety_result_en['name']).to eq 'name in english'
    expect(variety_result_es['id']).to eq variety_id
    expect(variety_result_es['name']).to eq 'name in spanish'
  end

  it 'falls back to a language when the one requested is not available' do
    query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			variety(id: $id, language: $language){
				id
        name
        createdAt
        updatedAt
			}
		}
    GRAPHQL

    variety = create(:variety, :public, name: 'name in english')
    variety.name_es = 'name in spanish'
    variety.save

    variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
    result_en = PlantApiSchema.execute(query_string, variables: { id: variety_id, language: 'en' })
    result_fr = PlantApiSchema.execute(query_string, variables: { id: variety_id, language: 'fr' })

    variety_result_en = result_en['data']['variety']
    variety_result_fr = result_fr['data']['variety']
    # Make sure the query worked
    expect(variety_result_en['id']).to eq variety_id
    expect(variety_result_en['name']).to eq 'name in english'
    expect(variety_result_fr['id']).to eq variety_id
    expect(variety_result_fr['name']).to eq 'name in english'
  end

  describe 'translations attribute' do
    it 'returns a list of languages when requested' do
      query_string = <<-GRAPHQL
			query($id: ID!){
				variety(id: $id){
					id
					name
					translations{
						locale
						description
						name
					}
				}
			}
      GRAPHQL

      variety = create(:variety, :public, name: 'nameen')
      variety.name_es = 'namees'
      variety.description_en = 'descriptionen'
      variety.description_es = 'descriptiones'
      variety.save

      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
      result = PlantApiSchema.execute(query_string, variables: { id: variety_id })

      variety_result = result['data']['variety']

      expect(variety_result['id']).to eq variety_id
      expect(variety_result['translations']).to be_kind_of Array
      expect(variety_result['translations'].length).to eq 2

      result_en = variety_result['translations'].detect { |l| l['locale'] == 'en' }
      result_es = variety_result['translations'].detect { |l| l['locale'] == 'es' }

      expect(result_en['name']).to eq 'nameen'
      expect(result_es['name']).to eq 'namees'
      expect(result_en['description']).to eq 'descriptionen'
    end
  end

  describe 'images attribute' do
    it 'returns a list of scoped image objects' do
      query_string = <<-GRAPHQL
			query($id: ID!){
				variety(id: $id){
					images{
						nodes{
							id
							name
							baseUrl
						}
					}
				}
			}
      GRAPHQL

      variety = create(:variety, :public, name: 'variety a')
      create(:image, :public, name: 'public_name', imageable: variety)
      create(:image, :private, name: 'private_name', owned_by: 'not me', imageable: variety)
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})

      result = PlantApiSchema.execute(query_string, variables: { id: variety_id })
      images_result = result['data']['variety']['images']['nodes']
      images_result_public = images_result.detect { |i| i['name'] == 'public_name' }
      images_result_private = images_result.detect { |i| i['name'] == 'private_name' }
      expect(images_result.count).to eq 1
      expect(images_result_public).to_not be nil
      expect(images_result_private).to be nil
    end
  end
end
