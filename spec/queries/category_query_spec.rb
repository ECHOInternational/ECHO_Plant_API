require 'rails_helper'

RSpec.describe "Category Query", type: :graphql_query do

  before :each do
  	Mobility.locale = nil
  end

  it "loads categories by ID" do
	  query_string = <<-GRAPHQL
		query($id: ID!){
			category(id: $id){
				id
				name
			}
		}
	  GRAPHQL

	  category = create(:category, :public, name: "loaded by id")
	  category_id = PlantApiSchema.id_from_object(category, Category, {})
	  result = PlantApiSchema.execute(query_string, variables: { id: category_id })

	  category_result = result["data"]["category"]
	  # Make sure the query worked
	  expect(category_result["id"]).to eq category_id
	  expect(category_result["name"]).to eq "loaded by id"
	end

    it "does not load categories for which the user is not authorized" do
	  query_string = <<-GRAPHQL
		query($id: ID!){
			category(id: $id){
				id
				name
			}
		}
	  GRAPHQL

	  category = create(:category, :private, name: "Private Category")
	  category_id = PlantApiSchema.id_from_object(category, Category, {})

	  expect {
	  	PlantApiSchema.execute(query_string, variables: { id: category_id })
	  }.to raise_error(ActiveRecord::RecordNotFound)
	end

	context "when user is authenticated" do
		it "loads owned records" do

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

		  category = create(:category, :private, name: "Private Category", owned_by: current_user.email)
		  category_id = PlantApiSchema.id_from_object(category, Category, {})

		  result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: category_id })

		  category_result = result["data"]["category"]
		  # Make sure the query worked
		  expect(category_result["id"]).to eq category_id
		  expect(category_result["name"]).to eq "Private Category"
		  expect(category_result["ownedBy"]).to eq current_user.email
		end
	end

	context "when user is admin" do
		it "loads unowned records" do

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

		  category = create(:category, :private, name: "Private Category", owned_by: "nottheadmin")
		  category_id = PlantApiSchema.id_from_object(category, Category, {})

		  result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: category_id })

		  category_result = result["data"]["category"]
		  # Make sure the query worked
		  expect(category_result["id"]).to eq category_id
		  expect(category_result["name"]).to eq "Private Category"
		  expect(category_result["ownedBy"]).to eq "nottheadmin"
		end
	end


    it "loads categories in the specified language" do
	  query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			category(id: $id, language: $language){
				id
				name
			}
		}
	  GRAPHQL

	  category = create(:category, :public, name: "name in english")
	  category.name_es = "name in spanish"
	  category.save

	  category_id = PlantApiSchema.id_from_object(category, Category, {})
	  result_en = PlantApiSchema.execute(query_string, variables: { id: category_id, language: "en" })
	  result_es = PlantApiSchema.execute(query_string, variables: { id: category_id, language: "es" })

	  category_result_en = result_en["data"]["category"]
  	  category_result_es = result_es["data"]["category"]
	  # Make sure the query worked
	  expect(category_result_en["id"]).to eq category_id
	  expect(category_result_en["name"]).to eq "name in english"
	  expect(category_result_es["id"]).to eq category_id
	  expect(category_result_es["name"]).to eq "name in spanish"

	end

	it "falls back to a language when the one requested is not available" do
	  query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			category(id: $id, language: $language){
				id
				name
			}
		}
	  GRAPHQL

	  category = create(:category, :public, name: "name in english")
	  category.name_es = "name in spanish"
	  category.save

	  category_id = PlantApiSchema.id_from_object(category, Category, {})
	  result_en = PlantApiSchema.execute(query_string, variables: { id: category_id, language: "en" })
	  result_fr = PlantApiSchema.execute(query_string, variables: { id: category_id, language: "fr" })
	  
	  category_result_en = result_en["data"]["category"]
  	  category_result_fr = result_fr["data"]["category"]
	  # Make sure the query worked
	  expect(category_result_en["id"]).to eq category_id
	  expect(category_result_en["name"]).to eq "name in english"
	  expect(category_result_fr["id"]).to eq category_id
	  expect(category_result_fr["name"]).to eq "name in english"

	end





end
