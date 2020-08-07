require 'rails_helper'

# argument :image_id, ID, "The ID for this image. This should be sourced from an upload.", required: true
# argument :object_id, ID, "The ID for the object to which the image should be attached.", required: true
# argument :name, String, "The translatable name of the image." required: true
# argument :description, String, "A translatable description of the image", required: false
# argument :attribution, String, "The copyright or attribution statement for the image.", required: false
# argument :language, String, "Language of the translatable fields supplied", required: false
# argument :bucket, String, "The S3 bucket where the image is stored.", required: true
# argument :key, String, "


# field :uuid, ID, "The internal database ID for an image", null: false, method: :id
# field :name, String, "The translated name of an image", null: true
# field :description, String, "A translated description of an image", null: true
# field :attribution, String, "Copyright and attribution data", null: true
# field :base_url, String, "The URL for the image", null: false
# field :image_attributes, [Types::ImageAttributeType], null: false
# field :created_by, String, "The user ID of an image's creator", null: true
# field :owned_by, String, "The user ID of an image's owner", null: true



RSpec.describe "Create Image Mutation", type: :graphql_mutation do

	let(:current_user) { nil }
	let(:query_string) { <<-GRAPHQL
		mutation($input: CreateImageInput!){
			createImage(input: $input){
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


  context "when user is not authenticated" do
      let(:current_user) { nil }
      let(:imageable) {create(:category)}
      it "returns an error when called" do
        imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
  		expect {
  			PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
				input: {
					imageId: "da5818be-da49-428f-87e6-e944dbb502f9",
                    objectId: imageable_id,
                    bucket: "images.us-east-1.echocommunity.org",
                    key: "a file name",
                    name: "newly created record",
                    description: "with an attached description",
                    language: "en"
				}
			})
  		}.to raise_error(Pundit::NotAuthorizedError)
  	end
  end

  context "when user is read only" do
       let(:current_user) { build(:user, :readonly) }
       let(:imageable) {create(:category)}
       it "returns an error when called" do
        imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
	  	 expect {
	  	 	PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
				input: {
                    imageId: "da5818be-da49-428f-87e6-e944dbb502f9",
                    objectId: imageable_id,
                    bucket: "images.us-east-1.echocommunity.org",
                    key: "a file name",
                    name: "newly created record",
                    description: "with an attached description",
                    language: "en"
				}
			})
	  	}.to raise_error(Pundit::NotAuthorizedError)
	  end
  end

  context "when user is authenticated" do
      let(:current_user) { build(:user, :readwrite) }
      let(:imageable) {create(:category, owned_by: current_user.email)}
      before :each do
        imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
		@result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
			input: {
                imageId: "da5818be-da49-428f-87e6-e944dbb502f9",
                objectId: imageable_id,
                bucket: "images.us-east-1.echocommunity.org",
                key: "a file name",
				name: "newly created record",
				description: "with an attached description",
				language: "en"
			}
		})
	end
    it "completes successfully" do
		expect(@result).to_not include "errors"
		expect(@result).to include "data"
	end

  	it "creates a record" do
		image_result = @result["data"]["createImage"]["image"]
		expect(image_result["name"]).to eq "newly created record"
		expect(image_result["description"]).to eq "with an attached description"

		created_image = Image.find image_result["uuid"]
		expect(created_image).to_not be nil
		expect(created_image.name).to eq "newly created record"
  	end


  	it "sets ownership to the current user" do
		image_result = @result["data"]["createImage"]["image"]
		expect(image_result["ownedBy"]).to eq current_user.email
  	end
  	it "sets creator to the current user" do
		image_result = @result["data"]["createImage"]["image"]
		expect(image_result["createdBy"]).to eq current_user.email
  	end

  	
  end
  describe "parameters" do
      let(:current_user) { build(:user, :readwrite) }
      let(:imageable) {create(:category, owned_by: current_user.email)}

  	describe "language" do
          it "sets the language" do
            imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
	  		es_result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
				input: {
					imageId: "da5818be-da49-428f-87e6-e944dbb502f9",
                    objectId: imageable_id,
                    bucket: "images.us-east-1.echocommunity.org",
                    key: "a file name",
				    name: "newly created record",
				    description: "with an attached description",
				    language: "es"
				}
            })
			image_es_result = es_result["data"]["createImage"]["image"]
			created_image_es = Image.find image_es_result["uuid"]

			expect(created_image_es.translations).to include "es"
			expect(created_image_es.translations).to_not include "en"
	  	end
  	end
  	describe "visibility" do
          it "sets the visibility" do
            imageable_id = PlantApiSchema.id_from_object(imageable, Category, {})
	  		result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { 
				input: {
                    name: "a public record",
                    imageId: "da5818be-da49-428f-87e6-e944dbb502f9",
                    objectId: imageable_id,
                    bucket: "images.us-east-1.echocommunity.org",
                    key: "a file name",
				    description: "with an attached description",
					visibility: "PUBLIC"
				}
            })
			image_result = result["data"]["createImage"]["image"]
			created_image = Image.find image_result["uuid"]
			expect(created_image.visibility_public?).to be true
			expect(created_image.visibility_private?).to be false
	  	end
  	end
  end
end
