# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Create Image Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: CreateImageInput!){
			createImage(input: $input){
        errors {
          field,
          value,
          message,
          code,
        }
        image{
                    id
                    uuid
                    name
                    description
                    attribution
                    baseUrl
                    createdBy
					ownedBy
					imageAttributes{
						id
					}
				}
			}
		}
    GRAPHQL
  }

  before :each do
    Mobility.locale = nil
  end

  context 'when user is not authenticated' do
    let(:current_user) { nil }
    let(:imageable) { create(:category) }
    it 'returns an error when called' do
      imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})

      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          imageId: 'da5818be-da49-428f-87e6-e944dbb502f9',
                                          objectId: imageable_id,
                                          bucket: 'images.us-east-1.echocommunity.org',
                                          key: 'a file name',
                                          name: 'newly created record',
                                          description: 'with an attached description',
                                          language: 'en'
                                        }
                                      })
      expect(result['data']).to be_nil
      expect(result['errors']).to_not be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 401
    end
  end

  context 'when user is read only' do
    let(:current_user) { build(:user, :readonly) }
    let(:imageable) { create(:category) }
    it 'returns an error when called' do
      imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          imageId: 'da5818be-da49-428f-87e6-e944dbb502f9',
                                          objectId: imageable_id,
                                          bucket: 'images.us-east-1.echocommunity.org',
                                          key: 'a file name',
                                          name: 'newly created record',
                                          description: 'with an attached description',
                                          language: 'en'
                                        }
                                      })
      expect(result['data']).to be_nil
      expect(result['errors']).to_not be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 403
    end
  end

  context 'when user is authenticated' do
    let(:current_user) { build(:user, :readwrite) }
    let(:imageable) { create(:category, owned_by: current_user.email) }
    before :each do
      imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           imageId: 'da5818be-da49-428f-87e6-e944dbb502f9',
                                           objectId: imageable_id,
                                           bucket: 'images.us-east-1.echocommunity.org',
                                           key: 'a file name',
                                           name: 'newly created record',
                                           description: 'with an attached description',
                                           language: 'en'
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'creates a record' do
      image_result = @result['data']['createImage']['image']
      expect(image_result['name']).to eq 'newly created record'
      expect(image_result['description']).to eq 'with an attached description'

      created_image = Image.find image_result['uuid']
      expect(created_image).to_not be nil
      expect(created_image.name).to eq 'newly created record'
    end

    it 'sets ownership to the current user' do
      image_result = @result['data']['createImage']['image']
      expect(image_result['ownedBy']).to eq current_user.email
    end
    it 'sets creator to the current user' do
      image_result = @result['data']['createImage']['image']
      expect(image_result['createdBy']).to eq current_user.email
    end
  end
  describe 'parameters' do
    let(:current_user) { build(:user, :readwrite) }
    let(:imageable) { create(:category, owned_by: current_user.email) }

    describe 'image_attributes' do
      it 'adds an array of provided attributes' do
        imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
        attr_a = create(:image_attribute)
        attr_b = create(:image_attribute)
        attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
        attr_b_id = PlantApiSchema.id_from_object(attr_b, ImageAttribute, {})

        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            imageId: 'da5818be-da49-428f-87e6-e944dbb502f9',
                                            objectId: imageable_id,
                                            bucket: 'images.us-east-1.echocommunity.org',
                                            key: 'a file name',
                                            name: 'newly created record',
                                            description: 'with an attached description',
                                            language: 'es',
                                            imageAttributeIds: [attr_a_id, attr_b_id]
                                          }
                                        })
        image_result = result['data']['createImage']['image']
        created_image = Image.find image_result['uuid']

        expect(created_image.image_attributes).to include attr_a
        expect(created_image.image_attributes).to include attr_b
      end
      it "succeeds with included errors when the provided attribute doesn't exist" do
        imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
        attr_a = create(:image_attribute)
        attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
        attr_b_id = "#{attr_a_id[0...-4]}fake"

        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            imageId: 'da5818be-da49-428f-87e6-e944dbb502f9',
                                            objectId: imageable_id,
                                            bucket: 'images.us-east-1.echocommunity.org',
                                            key: 'a file name',
                                            name: 'newly created record',
                                            description: 'with an attached description',
                                            language: 'es',
                                            imageAttributeIds: [attr_a_id, attr_b_id]
                                          }
                                        })

        expect(result).to_not include('errors')
        expect(result).to include('data')
        image_result = result['data']['createImage']['image']
        error_result = result['data']['createImage']['errors']
        expect(error_result.count).to eq 1
        expect(error_result[0]['field']).to eq 'imageAttributeIds'
        expect(error_result[0]['value']).to eq attr_b_id
        expect(error_result[0]['code']).to eq 404
        created_image = Image.find image_result['uuid']
        expect(created_image.image_attributes).to include attr_a
        expect(created_image.image_attributes.count).to eq 1
      end
    end

    describe 'language' do
      it 'sets the language' do
        imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
        es_result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                             input: {
                                               imageId: 'da5818be-da49-428f-87e6-e944dbb502f9',
                                               objectId: imageable_id,
                                               bucket: 'images.us-east-1.echocommunity.org',
                                               key: 'a file name',
                                               name: 'newly created record',
                                               description: 'with an attached description',
                                               language: 'es'
                                             }
                                           })
        image_es_result = es_result['data']['createImage']['image']
        created_image_es = Image.find image_es_result['uuid']

        expect(created_image_es.translations).to include 'es'
        expect(created_image_es.translations).to_not include 'en'
      end
    end
    describe 'visibility' do
      it 'sets the visibility' do
        imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            name: 'a public record',
                                            imageId: 'da5818be-da49-428f-87e6-e944dbb502f9',
                                            objectId: imageable_id,
                                            bucket: 'images.us-east-1.echocommunity.org',
                                            key: 'a file name',
                                            description: 'with an attached description',
                                            visibility: 'PUBLIC'
                                          }
                                        })
        image_result = result['data']['createImage']['image']
        created_image = Image.find image_result['uuid']
        expect(created_image.visibility_public?).to be true
        expect(created_image.visibility_private?).to be false
      end
    end
  end
end
