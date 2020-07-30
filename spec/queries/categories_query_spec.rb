require 'rails_helper'

RSpec.describe "Categories Query", type: :graphql_query do
	before :each do
		Mobility.locale = nil
	end
  
	it "returns a list of categories" do
	  query_string = <<-GRAPHQL
		query{
			categories{
				nodes {
					id
					name
				}
			}
		}
	  GRAPHQL

	  category_a = create(:category, :public, name: "category a")
  	  category_b = create(:category, :public, name: "category b")

	  category_a_id = PlantApiSchema.id_from_object(category_a, Category, {})
	  category_b_id = PlantApiSchema.id_from_object(category_b, Category, {})
	  
	  result = PlantApiSchema.execute(query_string)

	  category_result = result["data"]["categories"]["nodes"]
	  
	  result_a = category_result.detect {|c| c["id"] == category_a_id}
	  result_b = category_result.detect {|c| c["id"] == category_b_id}

	  expect(result_a["id"]).to eq category_a_id
	  expect(result_b["id"]).to eq category_b_id
	end


    it "does not load categories for which the user is not authorized" do
	  query_string = <<-GRAPHQL
		query{
			categories{
				nodes{
					id
					name
				}
			}
		}
	  GRAPHQL

	  category_a = create(:category, :public, name: "category a")
  	  category_b = create(:category, :private, name: "category b")

	  category_a_id = PlantApiSchema.id_from_object(category_a, Category, {})
	  category_b_id = PlantApiSchema.id_from_object(category_b, Category, {})
	  
	  result = PlantApiSchema.execute(query_string)

	  category_result = result["data"]["categories"]["nodes"]
	  
	  result_a = category_result.detect {|c| c["id"] == category_a_id}
	  result_b = category_result.detect {|c| c["id"] == category_b_id}

	  expect(result_a["id"]).to eq category_a_id
	  expect(result_b).to be_nil
	end

	context "when user is authenticated" do
		it "loads owned records" do

		  current_user = build(:user)

		  query_string = <<-GRAPHQL
			query{
				categories{
					nodes{
						id
						name
						ownedBy
					}
				}
			}
		  GRAPHQL

		  private_category_a = create(:category, :private, name: "Private Category A", owned_by: current_user.email)
  		  private_category_b = create(:category, :private, name: "Private Category B", owned_by: current_user.email)
  		  private_category_c = create(:category, :private, name: "Private Category C", owned_by: "somebody_else")

  		  private_category_a_id = PlantApiSchema.id_from_object(private_category_a, Category, {})
  		  private_category_b_id = PlantApiSchema.id_from_object(private_category_b, Category, {})
  		  private_category_c_id = PlantApiSchema.id_from_object(private_category_c, Category, {})

		  result = PlantApiSchema.execute(query_string, context: { current_user: current_user })

		  category_result = result["data"]["categories"]["nodes"]
		  
		  result_a = category_result.detect {|c| c["id"] == private_category_a_id}
		  result_b = category_result.detect {|c| c["id"] == private_category_b_id}
  		  result_c = category_result.detect {|c| c["id"] == private_category_c_id}


		  expect(result_a["id"]).to eq private_category_a_id
		  expect(result_b["id"]).to eq private_category_b_id
		  expect(result_c).to be_nil

		end

		describe "visibility filter" do
			describe "when user is not admin" do
				before :each do
					@current_user = build(:user)

					@query_string = <<-GRAPHQL
						query($visibility: Visibility){
							categories(visibility: $visibility){
								nodes{
									id
									name
									ownedBy
								}
							}
						}
					GRAPHQL

					@public_category = create(:category, :public, name: "Public Category", owned_by: @current_user.email)
					@private_category = create(:category, :private, name: "Private Category", owned_by: @current_user.email)
					@draft_category = create(:category, :draft, name: "Draft Category", owned_by: @current_user.email)
					@deleted_category = create(:category, :deleted, name: "Deleted Category", owned_by: @current_user.email)
					@unowned_public_category = create(:category, :public, name: "Unowned Public Category", owned_by: "not_me")
					@unowned_private_category = create(:category, :private, name: "Unowned Private Category", owned_by: "not_me")
					@unowned_draft_category = create(:category, :draft, name: "Unowned Draft Category", owned_by: "not_me")
					@unowned_deleted_category = create(:category, :deleted, name: "Unowned Deleted Category", owned_by: "not_me")
				end
				it "shows only public records when public" do
					result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: {visibility: "PUBLIC" })
					category_result = result["data"]["categories"]["nodes"]

					expect(category_result.length).to eq 2
					expect(category_result[0]["name"]).to eq("Public Category") | eq("Unowned Public Category")
					expect(category_result[1]["name"]).to eq("Public Category") | eq("Unowned Public Category")
				end
				
				it "shows only private records when private" do
					result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: {visibility: "PRIVATE" })
					category_result = result["data"]["categories"]["nodes"]

					expect(category_result.length).to eq 1
					expect(category_result[0]["name"]).to eq("Private Category")
				end

				it "shows only draft records when draft" do
					result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: {visibility: "DRAFT" })
					category_result = result["data"]["categories"]["nodes"]

					expect(category_result.length).to eq 1
					expect(category_result[0]["name"]).to eq("Draft Category")
				end


				it "shows only deleted records when deleted" do
					result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: {visibility: "DELETED" })
					category_result = result["data"]["categories"]["nodes"]

					expect(category_result.length).to eq 1
					expect(category_result[0]["name"]).to eq("Deleted Category")
				end

				it "show both public and private records when visible" do
					result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: {visibility: "VISIBLE" })
					category_result = result["data"]["categories"]["nodes"]

					expect(category_result.length).to eq 3
					expect(category_result[0]["name"]).to eq("Public Category") | eq("Unowned Public Category") | eq("Private Category")
					expect(category_result[1]["name"]).to eq("Public Category") | eq("Unowned Public Category") | eq("Private Category")
					expect(category_result[2]["name"]).to eq("Public Category") | eq("Unowned Public Category") | eq("Private Category")
				end
			end
			describe "when user is an admin" do
				before :each do
					@current_user = build(:user, :admin)

					@query_string = <<-GRAPHQL
						query($visibility: Visibility){
							categories(visibility: $visibility){
								nodes{
									id
									name
									ownedBy
								}
							}
						}
					GRAPHQL

					@public_category = create(:category, :public, name: "Public Category", owned_by: @current_user.email)
					@private_category = create(:category, :private, name: "Private Category", owned_by: @current_user.email)
					@draft_category = create(:category, :draft, name: "Draft Category", owned_by: @current_user.email)
					@deleted_category = create(:category, :deleted, name: "Deleted Category", owned_by: @current_user.email)
					@unowned_public_category = create(:category, :public, name: "Unowned Public Category", owned_by: "not_me")
					@unowned_private_category = create(:category, :private, name: "Unowned Private Category", owned_by: "not_me")
					@unowned_draft_category = create(:category, :draft, name: "Unowned Draft Category", owned_by: "not_me")
					@unowned_deleted_category = create(:category, :deleted, name: "Unowned Deleted Category", owned_by: "not_me")
				end
				
				it "allows access to other user's private records" do
					result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: {visibility: "PRIVATE" })
					category_result = result["data"]["categories"]["nodes"]

					expect(category_result.length).to eq 2
					expect(category_result[0]["name"]).to eq("Private Category").or eq("Unowned Private Category")
					expect(category_result[1]["name"]).to eq("Private Category").or eq("Unowned Private Category")
				end
			end
		end
	end

	describe "sortDirecton parameter" do
		before :each do
			@query_string = <<-GRAPHQL
				query($sortDirection: SortDirection){
					categories(sortDirection: $sortDirection){
						nodes{
							id
							name
						}
					}
				}
			GRAPHQL

			create(:category, :public, name: "a")
			create(:category, :public, name: "d")
			create(:category, :public, name: "c")
			create(:category, :public, name: "b")
		end

		it "sorts ascending by name" do
			result = PlantApiSchema.execute(@query_string, variables: {sortDirection: "ASC" })
			category_result = result["data"]["categories"]["nodes"]

			expect(category_result[0]["name"]).to eq "a"
			expect(category_result[1]["name"]).to eq "b"
			expect(category_result[2]["name"]).to eq "c"
			expect(category_result[3]["name"]).to eq "d"
		end
		it "sorts descending by name" do
			result = PlantApiSchema.execute(@query_string, variables: {sortDirection: "DESC" })
			category_result = result["data"]["categories"]["nodes"]

			expect(category_result[0]["name"]).to eq "d"
			expect(category_result[1]["name"]).to eq "c"
			expect(category_result[2]["name"]).to eq "b"
			expect(category_result[3]["name"]).to eq "a"
		end


	end

	describe "ownedBy filter" do
		before :each do
			@current_user = build(:user, :admin)

			@query_string = <<-GRAPHQL
				query($ownedBy: String){
					categories(ownedBy: $ownedBy, visibility: PRIVATE){
						nodes{
							id
							name
							ownedBy
						}
					}
				}
			GRAPHQL

			create(:category, :private, owned_by: @current_user.email)
			create(:category, :private, owned_by: "not_me")
			create(:category, :private, owned_by: "not_me_either")
		end
		
		it "does not limit when nil" do
			result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: {ownedBy: nil })
			category_result = result["data"]["categories"]["nodes"]

			expect(category_result.length).to eq 3
		end

		it "limits results to the specified user for owned records" do
			result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: {ownedBy: @current_user.email })
			category_result = result["data"]["categories"]["nodes"]

			expect(category_result.length).to eq 1
			expect(category_result[0]["ownedBy"]).to eq(@current_user.email)
		end

		it "limits results to the specified user for unowned records" do
			result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: {ownedBy: "not_me" })
			category_result = result["data"]["categories"]["nodes"]

			expect(category_result.length).to eq 1
			expect(category_result[0]["ownedBy"]).to eq("not_me")
		end
	end

	describe "name filter" do
		before :each do
			@current_user = build(:user, :admin)

			@query_string = <<-GRAPHQL
				query($name: String){
					categories(name: $name, visibility: PUBLIC){
						nodes{
							id
							name
						}
					}
				}
			GRAPHQL

			create(:category, :public, name: "Happy Man")
			create(:category, :public, name: "Sad Girl")
			create(:category, :public, name: "Mad Girl")
			create(:category, :public, name: "Happy Girl")
			create(:category, :public, name: "Orange Boy")
		end
		
		it "does not limit when nil" do
			result = PlantApiSchema.execute(@query_string, variables: {name: nil })
			category_result = result["data"]["categories"]["nodes"]

			expect(category_result.length).to eq 5
		end

		it "can return single results" do
			result = PlantApiSchema.execute(@query_string, variables: {name: "orange" })
			category_result = result["data"]["categories"]["nodes"]
			expect(category_result.length).to eq 1
		end

		it "can return multiple results" do
			result = PlantApiSchema.execute(@query_string, variables: {name: "girl" })
			category_result = result["data"]["categories"]["nodes"]

			expect(category_result.length).to eq 3
		end
	end


	it "returns categories in the specified language with fallbacks" do
	  query_string = <<-GRAPHQL
		query($language: String){
			categories(language: $language){
				nodes {
					id
					name
				}
			}
		}
	  GRAPHQL

	  category_a = create(:category, :public, name: "category a name en")
  	  category_b = create(:category, :public, name: "category b name en")
  	  category_b.name_es = "category b name es"
  	  category_b.save

	  category_a_id = PlantApiSchema.id_from_object(category_a, Category, {})
	  category_b_id = PlantApiSchema.id_from_object(category_b, Category, {})
	  
	  # result = PlantApiSchema.execute(query_string)
  	  result_en = PlantApiSchema.execute(query_string, variables: {language: "en" })
	  result_es = PlantApiSchema.execute(query_string, variables: {language: "es" })

	  category_result_en = result_en["data"]["categories"]["nodes"]
  	  category_result_es = result_es["data"]["categories"]["nodes"]
	  
	  result_en_a = category_result_en.detect {|c| c["id"] == category_a_id}
	  result_en_b = category_result_en.detect {|c| c["id"] == category_b_id}

	  result_es_a = category_result_es.detect {|c| c["id"] == category_a_id}
	  result_es_b = category_result_es.detect {|c| c["id"] == category_b_id}

	  expect(result_en_a["name"]).to eq "category a name en"
	  expect(result_en_b["name"]).to eq "category b name en"

	  expect(result_es_a["name"]).to eq "category a name en"
	  expect(result_es_b["name"]).to eq "category b name es"

	end

	describe "totalCount attribute" do 
		it "counts all available records" do
		  query_string = <<-GRAPHQL
			query{
				categories{
					totalCount
				}
			}
		  GRAPHQL

		  create(:category, :public, name: "category a")
	  	  create(:category, :public, name: "category b")

		  
		  result = PlantApiSchema.execute(query_string)
		  total_count = result["data"]["categories"]["totalCount"]

		  expect(total_count).to eq 2
		end

		it "does not count unavailable records" do
		  query_string = <<-GRAPHQL
			query{
				categories{
					totalCount
				}
			}
		  GRAPHQL

		  create(:category, :public, name: "category a")
	  	  create(:category, :private, name: "category b")

		  
		  result = PlantApiSchema.execute(query_string)
		  total_count = result["data"]["categories"]["totalCount"]

		  expect(total_count).to eq 1
		end
	end

end
