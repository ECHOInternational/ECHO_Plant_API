require 'rails_helper'

RSpec.describe "Update Category Mutation", type: :graphql_mutation do
  let(:current_user) { nil }
  let(:category) { create(:category) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: UpdateCategoryInput!){
			updateCategory(input: $input){
				category{
					id
					name
					uuid
					description
					ownedBy
					createdBy
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
    it "returns an error when called" do
      category_id = PlantApiSchema.id_from_object(category, Category, {})
      expect {
        PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                 input: {
                                   categoryId: category_id,
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
    it "returns an error when called" do
      category_id = PlantApiSchema.id_from_object(category, Category, {})
      expect {
        PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                 input: {
                                   categoryId: category_id,
                                   name: "newly created record",
                                   description: "with an attached description",
                                   language: "en"
                                 }
                               })
      }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  context "when user is not an admin" do
    let(:current_user) { build(:user, :readwrite) }
    let(:category) { create(:category, owned_by: current_user.email, created_by: current_user.email, name: "a name", description: "a description") }

    context "when the user does not own the record" do
      let(:category) { create(:category, owned_by: "notme", created_by: "notme", name: "a name", description: "a description") }
      it "raises an error" do
        @category_id = PlantApiSchema.id_from_object(category, Category, {})
        expect {
          PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                   input: {
                                     categoryId: @category_id,
                                     name: "updated record to this",
                                     description: "and updated the description",
                                     language: "en"
                                   }
                                 })
        }.to raise_error(Pundit::NotAuthorizedError)
      end
    end
    context "when user owns the record" do
      before :each do
        @category_id = PlantApiSchema.id_from_object(category, Category, {})
        @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                           input: {
                                             categoryId: @category_id,
                                             name: "updated record to this",
                                             description: "and updated the description",
                                             language: "en"
                                           }
                                         })
      end
      it "completes successfully" do
        expect(@result).to_not include "errors"
        expect(@result).to include "data"
      end

      it "updates a record" do
        category_result = @result["data"]["updateCategory"]["category"]
        expect(category_result["name"]).to eq "updated record to this"
        expect(category_result["description"]).to eq "and updated the description"
      end

      it "can update records in the speficied language" do
        category_en_result = @result["data"]["updateCategory"]["category"]
        created_category_en = Category.find category_en_result["uuid"]
        expect(created_category_en.translations).to_not include "es"
        expect(created_category_en.translations).to include "en"

        es_result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                             input: {
                                               categoryId: @category_id,
                                               name: "added this in spanish",
                                               description: "with an attached description in spanish",
                                               language: "es"
                                             }
                                           })
        category_es_result = es_result["data"]["updateCategory"]["category"]
        created_category_es = Category.find category_es_result["uuid"]
        expect(created_category_es.translations).to include "en"
        expect(created_category_es.translations).to include "es"
      end

      it "can update the visibility status" do
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            categoryId: @category_id,
                                            visibility: "PUBLIC"
                                          }
                                        })
        category_result = result["data"]["updateCategory"]["category"]
        created_category = Category.find category_result["uuid"]

        expect(created_category.visibility_public?).to be true
        expect(created_category.visibility_private?).to be false
      end
    end
  end
end
