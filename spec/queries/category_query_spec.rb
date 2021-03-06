# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Category Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'loads categories by ID' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			category(id: $id){
				id
				name
			}
		}
    GRAPHQL

    category = create(:category, :public, name: 'loaded by id')
    category_id = PlantApiSchema.id_from_object(category, Category, {})
    result = PlantApiSchema.execute(query_string, variables: { id: category_id })

    category_result = result['data']['category']
    # Make sure the query worked
    expect(category_result['id']).to eq category_id
    expect(category_result['name']).to eq 'loaded by id'
  end

  it 'does not load categories for which the user is not authorized' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			category(id: $id){
				id
				name
			}
		}
    GRAPHQL

    category = create(:category, :private, name: 'Private Category')
    category_id = PlantApiSchema.id_from_object(category, Category, {})

    result = PlantApiSchema.execute(query_string, variables: { id: category_id })
    expect(result['data']['category']).to be nil
    expect(result['errors'].count).to eq 1
    expect(result['errors'][0]['extensions']['code']).to eq 404
  end

  context 'when user is authenticated' do
    it 'loads owned records' do
      current_user = build(:user)

      query_string = <<-GRAPHQL
			query($id: ID!){
				category(id: $id){
					id
					name
					ownedBy
				}
			}
      GRAPHQL

      category = create(:category, :private, name: 'Private Category', owned_by: current_user.email)
      category_id = PlantApiSchema.id_from_object(category, Category, {})

      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: category_id })

      category_result = result['data']['category']
      # Make sure the query worked
      expect(category_result['id']).to eq category_id
      expect(category_result['name']).to eq 'Private Category'
      expect(category_result['ownedBy']).to eq current_user.email
    end
  end

  context 'when user is admin' do
    it 'loads unowned records' do
      current_user = build(:user, :admin)

      query_string = <<-GRAPHQL
			query($id: ID!){
				category(id: $id){
					id
					name
					ownedBy
				}
			}
      GRAPHQL

      category = create(:category, :private, name: 'Private Category', owned_by: 'nottheadmin')
      category_id = PlantApiSchema.id_from_object(category, Category, {})

      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: category_id })

      category_result = result['data']['category']
      # Make sure the query worked
      expect(category_result['id']).to eq category_id
      expect(category_result['name']).to eq 'Private Category'
      expect(category_result['ownedBy']).to eq 'nottheadmin'
    end
  end

  it 'loads categories in the specified language' do
    query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			category(id: $id, language: $language){
				id
				name
			}
		}
    GRAPHQL

    category = create(:category, :public, name: 'name in english')
    category.name_es = 'name in spanish'
    category.save

    category_id = PlantApiSchema.id_from_object(category, Category, {})
    result_en = PlantApiSchema.execute(query_string, variables: { id: category_id, language: 'en' })
    result_es = PlantApiSchema.execute(query_string, variables: { id: category_id, language: 'es' })

    category_result_en = result_en['data']['category']
    category_result_es = result_es['data']['category']
    # Make sure the query worked
    expect(category_result_en['id']).to eq category_id
    expect(category_result_en['name']).to eq 'name in english'
    expect(category_result_es['id']).to eq category_id
    expect(category_result_es['name']).to eq 'name in spanish'
  end

  it 'falls back to a language when the one requested is not available' do
    query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			category(id: $id, language: $language){
				id
				name
			}
		}
    GRAPHQL

    category = create(:category, :public, name: 'name in english')
    category.name_es = 'name in spanish'
    category.save

    category_id = PlantApiSchema.id_from_object(category, Category, {})
    result_en = PlantApiSchema.execute(query_string, variables: { id: category_id, language: 'en' })
    result_fr = PlantApiSchema.execute(query_string, variables: { id: category_id, language: 'fr' })

    category_result_en = result_en['data']['category']
    category_result_fr = result_fr['data']['category']
    # Make sure the query worked
    expect(category_result_en['id']).to eq category_id
    expect(category_result_en['name']).to eq 'name in english'
    expect(category_result_fr['id']).to eq category_id
    expect(category_result_fr['name']).to eq 'name in english'
  end

  describe 'translations attribute' do
    it 'returns a list of languages when requested' do
      query_string = <<-GRAPHQL
			query($id: ID!){
				category(id: $id){
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

      category = create(:category, :public, name: 'nameen')
      category.name_es = 'namees'
      category.description_en = 'descriptionen'
      category.description_es = 'descriptiones'
      category.save

      category_id = PlantApiSchema.id_from_object(category, Category, {})
      result = PlantApiSchema.execute(query_string, variables: { id: category_id })

      category_result = result['data']['category']

      expect(category_result['id']).to eq category_id
      expect(category_result['translations']).to be_kind_of Array
      expect(category_result['translations'].length).to eq 2

      result_en = category_result['translations'].detect { |l| l['locale'] == 'en' }
      result_es = category_result['translations'].detect { |l| l['locale'] == 'es' }

      expect(result_en['name']).to eq 'nameen'
      expect(result_es['name']).to eq 'namees'
      expect(result_en['description']).to eq 'descriptionen'
    end
  end

  describe 'images attribute' do
    it 'returns a list of scoped image objects' do
      query_string = <<-GRAPHQL
			query($id: ID!){
				category(id: $id){
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

      category = create(:category, :public, name: 'category a')
      create(:image, :public, name: 'public_name', imageable: category)
      create(:image, :private, name: 'private_name', owned_by: 'not me', imageable: category)
      category_id = PlantApiSchema.id_from_object(category, Category, {})

      result = PlantApiSchema.execute(query_string, variables: { id: category_id })
      images_result = result['data']['category']['images']['nodes']
      images_result_public = images_result.detect { |i| i['name'] == 'public_name' }
      images_result_private = images_result.detect { |i| i['name'] == 'private_name' }
      expect(images_result.count).to eq 1
      expect(images_result_public).to_not be nil
      expect(images_result_private).to be nil
    end
  end
end
