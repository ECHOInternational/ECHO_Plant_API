# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Delete Image Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:image) { create(:image) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: DeleteImageInput!){
			deleteImage(input: $input){
				imageId
				errors{
          message
        }
			}
		}
    GRAPHQL
  }

  context 'when user is not authenticated' do
    let(:current_user) { nil }
    it 'returns an error when called' do
      image_id = PlantApiSchema.id_from_object(image, Image, {})
      expect {
        PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                 input: {
                                   imageId: image_id
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
                                   imageId: image_id
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
                                     imageId: @image_id
                                   }
                                 })
        }.to raise_error(Pundit::NotAuthorizedError)
      end
    end
    context 'when user owns the record' do
      before :each do
        @image_id = PlantApiSchema.id_from_object(image, Image, {})
      end
      it 'deletes the record' do
        record_id = image.id
        expect { Image.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            imageId: @image_id
                                          }
                                        })
        expect(result).to_not include 'errors'
        expect(result).to include 'data'
        expect(result['data']['deleteImage']).to include 'imageId'
        expect(result['data']['deleteImage']['imageId']).to eq @image_id
        expect { Image.find record_id }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
