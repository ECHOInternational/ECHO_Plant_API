# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Mutation Error' do
  context 'when the error is not generated by ActiveRecord' do
    let(:current_user) { build(:user) }
    let(:image) { create(:image, owned_by: current_user.email) }
    let(:attr_a) { create(:image_attribute) }
    let(:attr_b) { create(:image_attribute) }
    let(:query_string) {
      <<-GRAPHQL
      mutation($input: AddImageAttributesToImageInput!){
        addImageAttributesToImage(input: $input){
          errors{
            field
            value
            message
            code
          }
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

    before :each do
      @image_id = PlantApiSchema.id_from_object(image, Image, {})
      @attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
      @attr_b_id = "#{@attr_a_id[0...-4]}fake"
      @attr_c_id = "#{@attr_a_id[0...-4]}foke"
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           imageId: @image_id,
                                           imageAttributeIds: [@attr_a_id, @attr_b_id, @attr_c_id]
                                         }
                                       })
      @errors = @result['data']['addImageAttributesToImage']['errors']
    end

    it 'provides a well-formed error object' do
    end

    it 'contains a field key' do
      expect(@errors[0]).to include 'field'
    end
    it 'contains an optional value key' do
      expect(@errors[0]).to include 'value'
    end
    it 'contains a message key' do
      expect(@errors[0]).to include 'message'
    end
    it 'contains a code key' do
      expect(@errors[0]).to include 'code'
    end
    context 'when there are multiple errors' do
      it 'returns multiple error objects' do
        expect(@errors.count).to eq 2
      end
    end
  end

  context 'when the error is generated by ActiveRecord' do
    context 'when a record fails persistence' do
      let(:current_user) { build(:user) }
      let(:existing_record) { create(:image, owned_by: current_user.email) }
      let(:imageable) { create(:category, owned_by: current_user.email) }
      let(:query_string) {
        <<-GRAPHQL
        mutation($input: CreateImageInput!){
          createImage(input: $input){
            errors{
              field
              value
              message
              code
            }
            image{
              id
              uuid
              name
              imageAttributes{
                id
                name
              }
            }
          }
        }
        GRAPHQL
      }
      before :each do
        image_id = existing_record.id
        imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
        @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                           input: {
                                             imageId: image_id,
                                             objectId: imageable_id,
                                             bucket: 'images.us-east-1.echocommunity.org',
                                             key: 'a file name',
                                             name: 'newly created record',
                                             description: 'with an attached description'
                                           }
                                         })
        @errors = @result['data']['createImage']['errors']
      end
      it 'converts ActiveRecord errors to error objects' do
        expect(@result['errors']).to be nil
        expect(@errors.count).to be_positive
      end
      it 'contains a field key that matches a graphql field name' do
        expect(@errors[0]).to include 'field'
        expect(@errors[0]['field']).to eq 'imageId'
      end
      it 'contains an optional value key' do
        expect(@errors[0]).to include 'value'
        expect(@errors[0]['value']).to be nil
      end
      it 'contains a message key' do
        expect(@errors[0]).to include 'message'
        expect(@errors[0]['message']).to_not be_empty
      end
      it 'contains a code key with value 400' do
        expect(@errors[0]).to include 'code'
        expect(@errors[0]['code']).to eq 400
      end
    end
    context 'when there are multiple errors' do
      let(:current_user) { build(:user) }
      let(:existing_record) { create(:image, owned_by: current_user.email) }
      let(:imageable) { create(:category, owned_by: current_user.email) }
      let(:query_string) {
        <<-GRAPHQL
        mutation($input: CreateImageInput!){
          createImage(input: $input){
            errors{
              field
              value
              message
              code
            }
            image{
              id
              uuid
              name
              imageAttributes{
                id
                name
              }
            }
          }
        }
        GRAPHQL
      }
      before :each do
        image_id = existing_record.id
        imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
        attr_a = create(:image_attribute)
        attr_a_id = PlantApiSchema.id_from_object(attr_a, ImageAttribute, {})
        attr_b_id = "#{attr_a_id[0...-4]}fake"
        attr_c_id = "#{attr_a_id[0...-4]}fike"
        @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                           input: {
                                             imageId: image_id,
                                             objectId: imageable_id,
                                             bucket: 'images.us-east-1.echocommunity.org',
                                             key: 'a file name',
                                             name: 'newly created record',
                                             description: 'with an attached description',
                                             imageAttributeIds: [attr_a_id, attr_b_id, attr_c_id]
                                           }
                                         })
        @errors = @result['data']['createImage']['errors']
      end

      it 'returns multiple error objects' do
        expect(@errors.count).to eq 3
      end
    end
    context 'when a record is not found' do
      it 'contains a field key that matches a graphql field name'
      it 'contains a value key with the record id that was not found'
      it 'contains a message key'
      it 'contains a code key with value 404'
    end
  end
end