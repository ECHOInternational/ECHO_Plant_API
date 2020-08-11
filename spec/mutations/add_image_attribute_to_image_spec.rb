# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Add Image Attributes To Image Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:image) { create(:image) }
  let(:attr_a) { create(:image_attribute) }
  let(:attr_b) { create(:image_attribute) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: AddImageAttributesToImageInput!){
			addImageAttributesToImage(input: $input){
				image{
					id
					uuid
					imageAttributes{
						id
						name
					}
				}
			}
		}
    GRAPHQL
  }

  context 'when the imageId is invalid' do
    it 'returns a record not found error' do
      real_image_id = PlantApiSchema.id_from_object(image, Image, {})
      fake_image_id = real_image_id[0...-4] + 'fake'
      attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          imageId: fake_image_id,
                                          imageAttributeIds: [attr_a_id]
                                        }
                                      })
      expect(result).to include 'data'
      expect(result).to include 'errors'
      expect(result['data']).to be nil
      expect(result['errors'].length).to eq 1
    end
  end

  context 'when the imageId is valid' do
    context 'when user is not authenticated' do
      let(:current_user) { nil }
      it 'returns an error when called' do
        image_id = PlantApiSchema.id_from_object(image, Image, {})
        attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
        expect {
          PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                   input: {
                                     imageId: image_id,
                                     imageAttributeIds: [attr_a_id]
                                   }
                                 })
        }.to raise_error(Pundit::NotAuthorizedError)
      end
    end

    context 'when user is read only' do
      let(:current_user) { build(:user, :readonly) }
      it 'returns an error when called' do
        image_id = PlantApiSchema.id_from_object(image, Image, {})
        attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
        expect {
          PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                   input: {
                                     imageId: image_id,
                                     imageAttributeIds: [attr_a_id]
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
          image_id = PlantApiSchema.id_from_object(image, Image, {})
          attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
          expect {
            PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                     input: {
                                       imageId: image_id,
                                       imageAttributeIds: [attr_a_id]
                                     }
                                   })
          }.to raise_error(Pundit::NotAuthorizedError)
        end
      end
      context 'when user owns the record' do
        context 'with one valid addition' do
          before :each do
            @image_id = PlantApiSchema.id_from_object(image, Image, {})
            @attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
            @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                               input: {
                                                 imageId: @image_id,
                                                 imageAttributeIds: [@attr_a_id]
                                               }
                                             })
          end
          it 'completes successfully' do
            expect(@result).to_not include 'errors'
            expect(@result).to include 'data'
          end

          it 'updates the record' do
            image_result = @result['data']['addImageAttributesToImage']['image']['imageAttributes']
            image_result_name_a = image_result.detect { |i| i['name'] == attr_a.name }
            expect(image_result_name_a).to_not be nil
          end
        end
        context 'with multiple additions' do
          before :each do
            @image_id = PlantApiSchema.id_from_object(image, Image, {})
            @attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
            @attr_b_id = PlantApiSchema.id_from_object(attr_b, ImageAttribute, {})
            @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                               input: {
                                                 imageId: @image_id,
                                                 imageAttributeIds: [@attr_a_id, @attr_b_id]
                                               }
                                             })
          end
          it 'completes successfully' do
            expect(@result).to_not include 'errors'
            expect(@result).to include 'data'
          end

          it 'updates the record' do
            image_result = @result['data']['addImageAttributesToImage']['image']['imageAttributes']
            image_result_name_a = image_result.detect { |i| i['name'] == attr_a.name }
            image_result_name_b = image_result.detect { |i| i['name'] == attr_b.name }
            expect(image_result_name_a).to_not be nil
            expect(image_result_name_b).to_not be nil
            expect(image.image_attributes.count).to eq 2
          end
        end
        context 'with both a valid and an invalid addition' do
          before :each do
            @image_id = PlantApiSchema.id_from_object(image, Image, {})
            @attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
            @attr_b_id = @attr_a_id[0...-4] + 'fake'
            @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                               input: {
                                                 imageId: @image_id,
                                                 imageAttributeIds: [@attr_a_id, @attr_b_id]
                                               }
                                             })
          end
          it 'completes successfully with both data and errors' do
            expect(@result).to include 'errors'
            expect(@result).to include 'data'
            expect(@result['errors'].count).to eq 1
          end

          it 'updates the record' do
            image_result = @result['data']['addImageAttributesToImage']['image']['imageAttributes']
            image_result_name_a = image_result.detect { |i| i['name'] == attr_a.name }
            expect(image_result_name_a).to_not be nil
            expect(image.image_attributes.count).to eq 1
          end
        end
      end
    end
  end
end
