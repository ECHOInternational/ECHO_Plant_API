# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Image Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:image) { create(:image) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: UpdateImageInput!){
			updateImage(input: $input){
				image{
                    id
                    uuid
                    name
                    description
                    attribution
                    baseUrl
                    createdBy
                    ownedBy
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
    it 'returns an error when called' do
      image_id = PlantApiSchema.id_from_object(image, Image, {})
      expect {
        PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                 input: {
                                   imageId: image_id,
                                   name: 'changing record',
                                   description: 'with a description change'
                                 }
                               })
      }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  context 'when user is read only' do
    let(:current_user) { build(:user, :readonly) }
    it 'returns an error when called' do
      image_id = PlantApiSchema.id_from_object(image, Image, {})
      expect {
        PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                 input: {
                                   imageId: image_id,
                                   name: 'newly created record',
                                   description: 'with an attached description'
                                 }
                               })
      }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  context 'when user is not an admin' do
    let(:current_user) { build(:user, :readwrite) }
    let(:image) { create(:image, owned_by: current_user.email, created_by: current_user.email, name: 'a name', description: 'a description') }

    context 'when the user does not own the record' do
      let(:image) { create(:image, owned_by: 'notme', created_by: 'notme', name: 'a name', description: 'a description') }
      it 'raises an error' do
        @image_id = PlantApiSchema.id_from_object(image, Image, {})
        expect {
          PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                   input: {
                                     imageId: @image_id,
                                     name: 'updated record to this',
                                     description: 'and updated the description',
                                     language: 'en'
                                   }
                                 })
        }.to raise_error(Pundit::NotAuthorizedError)
      end
    end
    context 'when user owns the record' do
      before :each do
        @image_id = PlantApiSchema.id_from_object(image, Image, {})
        @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                           input: {
                                             imageId: @image_id,
                                             name: 'updated record to this',
                                             description: 'and updated the description',
                                             language: 'en'
                                           }
                                         })
      end
      it 'completes successfully' do
        expect(@result).to_not include 'errors'
        expect(@result).to include 'data'
      end

      it 'updates a record' do
        image_result = @result['data']['updateImage']['image']
        expect(image_result['name']).to eq 'updated record to this'
        expect(image_result['description']).to eq 'and updated the description'
      end

      it 'can update records in the speficied language' do
        image_en_result = @result['data']['updateImage']['image']
        created_image_en = Image.find image_en_result['uuid']
        expect(created_image_en.translations).to_not include 'es'
        expect(created_image_en.translations).to include 'en'

        es_result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                             input: {
                                               imageId: @image_id,
                                               name: 'added this in spanish',
                                               description: 'with an attached description in spanish',
                                               language: 'es'
                                             }
                                           })
        image_es_result = es_result['data']['updateImage']['image']
        created_image_es = Image.find image_es_result['uuid']
        expect(created_image_es.translations).to include 'en'
        expect(created_image_es.translations).to include 'es'
      end

      it 'can update the visibility status' do
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            imageId: @image_id,
                                            visibility: 'PUBLIC'
                                          }
                                        })
        image_result = result['data']['updateImage']['image']
        created_image = Image.find image_result['uuid']

        expect(created_image.visibility_public?).to be true
        expect(created_image.visibility_private?).to be false
      end
    end
  end
end
