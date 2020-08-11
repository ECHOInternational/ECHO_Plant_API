require 'rails_helper'

RSpec.describe "ImageAttributes Query", type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it "returns a list of image attributes" do
    query_string = <<-GRAPHQL
		query{
			imageAttributes{
				nodes {
					id
					name
				}
			}
		}
    GRAPHQL

    image_attribute_a = create(:image_attribute, name: "image_attribute a")
    image_attribute_b = create(:image_attribute, name: "image_attribute b")

    image_attribute_a_id = PlantApiSchema.id_from_object(image_attribute_a, ImageAttribute, {})
    image_attribute_b_id = PlantApiSchema.id_from_object(image_attribute_b, ImageAttribute, {})

    result = PlantApiSchema.execute(query_string)
    image_attribute_result = result["data"]["imageAttributes"]["nodes"]

    result_a = image_attribute_result.detect { |c| c["id"] == image_attribute_a_id }
    result_b = image_attribute_result.detect { |c| c["id"] == image_attribute_b_id }

    expect(result_a["id"]).to eq image_attribute_a_id
    expect(result_b["id"]).to eq image_attribute_b_id
  end

  describe "name filter" do
    before :each do
      @current_user = build(:user, :admin)

      @query_string = <<-GRAPHQL
				query($name: String){
					imageAttributes(name: $name){
						nodes{
							id
							name
						}
					}
				}
      GRAPHQL

      create(:image_attribute,  name: "Happy Man")
      create(:image_attribute,  name: "Sad Girl")
      create(:image_attribute,  name: "Mad Girl")
      create(:image_attribute,  name: "Happy Girl")
      create(:image_attribute,  name: "Orange Boy")
    end

    it "does not limit when nil" do
      result = PlantApiSchema.execute(@query_string, variables: { name: nil })
      image_attribute_result = result["data"]["imageAttributes"]["nodes"]

      expect(image_attribute_result.length).to eq 5
    end

    it "can return single results" do
      result = PlantApiSchema.execute(@query_string, variables: { name: "orange" })
      image_attribute_result = result["data"]["imageAttributes"]["nodes"]
      expect(image_attribute_result.length).to eq 1
    end

    it "can return multiple results" do
      result = PlantApiSchema.execute(@query_string, variables: { name: "girl" })
      image_attribute_result = result["data"]["imageAttributes"]["nodes"]

      expect(image_attribute_result.length).to eq 3
    end
  end

  it "returns image_attributes in the specified language with fallbacks" do
    query_string = <<-GRAPHQL
		query($language: String){
			imageAttributes(language: $language){
				nodes {
					id
					name
				}
			}
		}
    GRAPHQL

    image_attribute_a = create(:image_attribute, name: "image_attribute a name en")
    image_attribute_b = create(:image_attribute, name: "image_attribute b name en")
    image_attribute_b.name_es = "image_attribute b name es"
    image_attribute_b.save

    image_attribute_a_id = PlantApiSchema.id_from_object(image_attribute_a, ImageAttribute, {})
    image_attribute_b_id = PlantApiSchema.id_from_object(image_attribute_b, ImageAttribute, {})

    # result = PlantApiSchema.execute(query_string)
    result_en = PlantApiSchema.execute(query_string, variables: { language: "en" })
    result_es = PlantApiSchema.execute(query_string, variables: { language: "es" })

    image_attribute_result_en = result_en["data"]["imageAttributes"]["nodes"]
    image_attribute_result_es = result_es["data"]["imageAttributes"]["nodes"]

    result_en_a = image_attribute_result_en.detect { |c| c["id"] == image_attribute_a_id }
    result_en_b = image_attribute_result_en.detect { |c| c["id"] == image_attribute_b_id }

    result_es_a = image_attribute_result_es.detect { |c| c["id"] == image_attribute_a_id }
    result_es_b = image_attribute_result_es.detect { |c| c["id"] == image_attribute_b_id }

    expect(result_en_a["name"]).to eq "image_attribute a name en"
    expect(result_en_b["name"]).to eq "image_attribute b name en"

    expect(result_es_a["name"]).to eq "image_attribute a name en"
    expect(result_es_b["name"]).to eq "image_attribute b name es"
  end

  describe "totalCount attribute" do
    it "counts all available records" do
      query_string = <<-GRAPHQL
			query{
				imageAttributes{
					totalCount
				}
			}
      GRAPHQL

      create(:image_attribute, name: "image_attribute a")
      create(:image_attribute, name: "image_attribute b")

      result = PlantApiSchema.execute(query_string)
      total_count = result["data"]["imageAttributes"]["totalCount"]

      expect(total_count).to eq 2
    end
  end
end
