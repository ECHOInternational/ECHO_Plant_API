require 'rails_helper'

RSpec.describe "Remove Image Attributes From Image Mutation", type: :graphql_mutation do

    let(:current_user) { nil }
    let(:image_attribute_a) { create(:image_attribute)}
    let(:image_attribute_b) { create(:image_attribute)}
	let(:image) { create(:image, image_attributes: [image_attribute_a, image_attribute_b]) }
	let(:query_string) { <<-GRAPHQL
		mutation($input: RemoveImageAttributesFromImageInput!){
			removeImageAttributesFromImage(input: $input){
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

	context "when the image does not exist" do
		it "returns a not found error" do
			image_id = PlantApiSchema.id_from_object(image, Image, {})
			fake_image_id = image_id[0...-4] + "fake"
			image_attribute_a_id = PlantApiSchema.id_from_object(image_attribute_a, ImageAttribute, {})
			image_attribute_b_id = PlantApiSchema.id_from_object(image_attribute_b, ImageAttribute, {})
			result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
				input: {
					imageId: fake_image_id,
					imageAttributeIds: [image_attribute_a_id]
				}
			})
			expect(result["data"]).to be nil
			expect(result["errors"].count).to eq 1
		end
	end

  context "when user is not authenticated" do
  	let(:current_user) { nil }
  	it "returns an error when called" do
        image_id = PlantApiSchema.id_from_object(image, Image, {})
        image_attribute_a_id = PlantApiSchema.id_from_object(image_attribute_a, ImageAttribute, {})
        image_attribute_b_id = PlantApiSchema.id_from_object(image_attribute_b, ImageAttribute, {})
  		expect {
  			PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
				input: {
                    imageId: image_id,
                    imageAttributeIds: [image_attribute_a_id]
				}
			})
  		}.to raise_error(Pundit::NotAuthorizedError)
  	end
  end

  context "when user is read only" do
  	 let(:current_user) { build(:user, :readonly) }
  	 it "returns an error when called" do
        image_id = PlantApiSchema.id_from_object(image, Image, {})
        image_attribute_a_id = PlantApiSchema.id_from_object(image_attribute_a, ImageAttribute, {})
        image_attribute_b_id = PlantApiSchema.id_from_object(image_attribute_b, ImageAttribute, {})
        expect {
            PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
                input: {
                    imageId: image_id,
                    imageAttributeIds: [image_attribute_a_id]
                }
            })
        }.to raise_error(Pundit::NotAuthorizedError)
	  end
  end

  context "when user is not an admin" do
  	let(:current_user) { build(:user, :readwrite) }
  	
  	context "when the user does not own the record" do
  		let(:image) { create(:image, owned_by: "notme", created_by: "notme", image_attributes: [image_attribute_a, image_attribute_b])}
  		it "raises an error" do
			image_id = PlantApiSchema.id_from_object(image, Image, {})
			image_attribute_a_id = PlantApiSchema.id_from_object(image_attribute_a, ImageAttribute, {})
			image_attribute_b_id = PlantApiSchema.id_from_object(image_attribute_b, ImageAttribute, {})
  			expect {
  				PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
					input: {
						imageId: image_id,
						imageAttributeIds: [image_attribute_a_id]
					}
				})
	  		}.to raise_error(Pundit::NotAuthorizedError)
  		end
  	end
	context "when user owns the record" do
		let(:image) { create(:image, owned_by: current_user.email, created_by: current_user.email, image_attributes: [image_attribute_a, image_attribute_b])}
		before :each do
			@image_id = PlantApiSchema.id_from_object(image, Image, {})
			@image_attribute_a_id = PlantApiSchema.id_from_object(image_attribute_a, ImageAttribute, {})
			@image_attribute_b_id = PlantApiSchema.id_from_object(image_attribute_b, ImageAttribute, {})
		end
		it "deletes a single record" do
			record_id = image.id
			expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_a.id) }.to_not raise_error(ActiveRecord::RecordNotFound)

			result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
				input: {
					imageId: @image_id,
					imageAttributeIds: [@image_attribute_a_id]
				}
			})
			expect(result).to_not include "errors"
			expect(result).to include "data"
			expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_a.id) }.to raise_error(ActiveRecord::RecordNotFound)
		end
		it "deletes multiple records" do
			record_id = image.id
			expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_a.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
			expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_b.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
			expect { 
				PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
					input: {
						imageId: @image_id,
						imageAttributeIds: [@image_attribute_a_id, @image_attribute_b_id]
					}
				})
			}.to change{ ImageAttributesImage.count }.by(-2)
		end
		context "when a passed image_attribute is invalid" do
			context "when the image_attribute doesn't exist" do
				before :each do
					@fake_image_attribute_id = @image_attribute_a_id[0...-4] + "fake"
				end
				it "returns both errors and data" do
					record_id = image.id
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_a.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_b.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
					result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
							input: {
								imageId: @image_id,
								imageAttributeIds: [@image_attribute_a_id, @image_attribute_b_id, @fake_image_attribute_id]
							}
						})
					expect(result["data"]["removeImageAttributesFromImage"]["image"]).to_not be nil
					expect(result["errors"].count).to eq 1
				end
				it "removes attributes that do exist" do
					record_id = image.id
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_a.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_b.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
					expect { 
						PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
							input: {
								imageId: @image_id,
								imageAttributeIds: [@image_attribute_a_id, @image_attribute_b_id, @fake_image_attribute_id]
							}
						})
					}.to change{ ImageAttributesImage.count }.by(-2)
				end
			end
			context "when the image doesn't have a relationship with the image_attribute" do
				let(:not_related_attribute) {create(:image_attribute)}
				before :each do
					@not_related_attribute_id = PlantApiSchema.id_from_object(not_related_attribute, ImageAttribute, {})
				end
				it "returns both errors and data" do
					record_id = image.id
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_a.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_b.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: not_related_attribute.id) }.to raise_error(ActiveRecord::RecordNotFound)
					result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
							input: {
								imageId: @image_id,
								imageAttributeIds: [@image_attribute_a_id, @not_related_attribute_id]
							}
						})
					expect(result["data"]["removeImageAttributesFromImage"]["image"]).to_not be nil
					expect(result["errors"].count).to eq 1
				end
				it "removes attributes that do exist" do
					record_id = image.id
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_a.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute_b.id) }.to_not raise_error(ActiveRecord::RecordNotFound)
					expect { ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: not_related_attribute.id) }.to raise_error(ActiveRecord::RecordNotFound)
					expect { 
						PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
							input: {
								imageId: @image_id,
								imageAttributeIds: [@image_attribute_a_id, @not_related_attribute_id]
							}
						})
					}.to change{ ImageAttributesImage.count }.by(-1)
				end
			end
		end
	  end
  end
end
