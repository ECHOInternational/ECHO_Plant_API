# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Image Attribute Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'loads image attributes by ID' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			imageAttribute(id: $id){
				id
				name
			}
		}
    GRAPHQL

    image_attribute = create(:image_attribute, name: 'loaded by id')
    image_attribute_id = PlantApiSchema.id_from_object(image_attribute, ImageAttribute, {})
    result = PlantApiSchema.execute(query_string, variables: { id: image_attribute_id })
    image_attribute_result = result['data']['imageAttribute']
    # Make sure the query worked
    expect(image_attribute_result['id']).to eq image_attribute_id
    expect(image_attribute_result['name']).to eq 'loaded by id'
  end

  it 'falls back to a language when the one requested is not available' do
    query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			imageAttribute(id: $id, language: $language){
				id
				name
			}
		}
    GRAPHQL

    image_attribute = create(:image_attribute, name: 'name in english')
    image_attribute.name_es = 'name in spanish'
    image_attribute.save

    image_attribute_id = PlantApiSchema.id_from_object(image_attribute, ImageAttribute, {})
    result_en = PlantApiSchema.execute(query_string, variables: { id: image_attribute_id, language: 'en' })
    result_fr = PlantApiSchema.execute(query_string, variables: { id: image_attribute_id, language: 'fr' })

    image_attribute_result_en = result_en['data']['imageAttribute']
    image_attribute_result_fr = result_fr['data']['imageAttribute']
    # Make sure the query worked
    expect(image_attribute_result_en['id']).to eq image_attribute_id
    expect(image_attribute_result_en['name']).to eq 'name in english'
    expect(image_attribute_result_fr['id']).to eq image_attribute_id
    expect(image_attribute_result_fr['name']).to eq 'name in english'
  end

  describe 'translations attribute' do
    it 'returns a list of languages when requested' do
      query_string = <<-GRAPHQL
			query($id: ID!){
				imageAttribute(id: $id){
					id
					name
					translations{
						locale
						name
					}
				}
			}
      GRAPHQL

      image_attribute = create(:image_attribute, name: 'nameen')
      image_attribute.name_es = 'namees'
      image_attribute.save

      image_attribute_id = PlantApiSchema.id_from_object(image_attribute, ImageAttribute, {})
      result = PlantApiSchema.execute(query_string, variables: { id: image_attribute_id })

      image_attribute_result = result['data']['imageAttribute']

      expect(image_attribute_result['id']).to eq image_attribute_id
      expect(image_attribute_result['translations']).to be_kind_of Array
      expect(image_attribute_result['translations'].length).to eq 2

      result_en = image_attribute_result['translations'].detect { |l| l['locale'] == 'en' }
      result_es = image_attribute_result['translations'].detect { |l| l['locale'] == 'es' }

      expect(result_en['name']).to eq 'nameen'
      expect(result_es['name']).to eq 'namees'
    end
  end
end
