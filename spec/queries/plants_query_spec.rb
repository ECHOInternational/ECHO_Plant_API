# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Plants Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'returns a list of plants' do
    query_string = <<-GRAPHQL
		query{
			plants{
				nodes {
					id
					scientificName
				}
			}
		}
    GRAPHQL

    plant_a = create(:plant, :public, scientific_name: 'plant a')
    plant_b = create(:plant, :public, scientific_name: 'plant b')

    plant_a_id = PlantApiSchema.id_from_object(plant_a, Plant, {})
    plant_b_id = PlantApiSchema.id_from_object(plant_b, Plant, {})

    result = PlantApiSchema.execute(query_string)

    plant_result = result['data']['plants']['nodes']

    result_a = plant_result.detect { |c| c['id'] == plant_a_id }
    result_b = plant_result.detect { |c| c['id'] == plant_b_id }

    expect(result_a['id']).to eq plant_a_id
    expect(result_b['id']).to eq plant_b_id
  end

  it 'does not load plants for which the user is not authorized' do
    query_string = <<-GRAPHQL
		query{
			plants{
				nodes{
					id
					scientificName
				}
			}
		}
    GRAPHQL

    plant_a = create(:plant, :public, scientific_name: 'plant a')
    plant_b = create(:plant, :private, scientific_name: 'plant b')

    plant_a_id = PlantApiSchema.id_from_object(plant_a, Plant, {})
    plant_b_id = PlantApiSchema.id_from_object(plant_b, Plant, {})

    result = PlantApiSchema.execute(query_string)

    plant_result = result['data']['plants']['nodes']

    result_a = plant_result.detect { |c| c['id'] == plant_a_id }
    result_b = plant_result.detect { |c| c['id'] == plant_b_id }

    expect(result_a['id']).to eq plant_a_id
    expect(result_b).to be_nil
  end

  context 'when user is authenticated' do
    it 'loads owned records' do
      current_user = build(:user)

      query_string = <<-GRAPHQL
			query{
				plants{
					nodes{
						id
						scientificName
						ownedBy
					}
				}
			}
      GRAPHQL

      private_plant_a = create(:plant, :private, scientific_name: 'Private Plant A', owned_by: current_user.email)
      private_plant_b = create(:plant, :private, scientific_name: 'Private Plant B', owned_by: current_user.email)
      private_plant_c = create(:plant, :private, scientific_name: 'Private Plant C', owned_by: 'somebody_else')

      private_plant_a_id = PlantApiSchema.id_from_object(private_plant_a, Plant, {})
      private_plant_b_id = PlantApiSchema.id_from_object(private_plant_b, Plant, {})
      private_plant_c_id = PlantApiSchema.id_from_object(private_plant_c, Plant, {})

      result = PlantApiSchema.execute(query_string, context: { current_user: current_user })

      plant_result = result['data']['plants']['nodes']

      result_a = plant_result.detect { |c| c['id'] == private_plant_a_id }
      result_b = plant_result.detect { |c| c['id'] == private_plant_b_id }
      result_c = plant_result.detect { |c| c['id'] == private_plant_c_id }

      expect(result_a['id']).to eq private_plant_a_id
      expect(result_b['id']).to eq private_plant_b_id
      expect(result_c).to be_nil
    end

    describe 'visibility filter' do
      describe 'when user is not admin' do
        before :each do
          @current_user = build(:user)

          @query_string = <<-GRAPHQL
						query($visibility: Visibility){
							plants(visibility: $visibility){
								nodes{
									id
									scientificName
									ownedBy
								}
							}
						}
          GRAPHQL

          @public_plant = create(:plant, :public, scientific_name: 'Public Plant', owned_by: @current_user.email)
          @private_plant = create(:plant, :private, scientific_name: 'Private Plant', owned_by: @current_user.email)
          @draft_plant = create(:plant, :draft, scientific_name: 'Draft Plant', owned_by: @current_user.email)
          @deleted_plant = create(:plant, :deleted, scientific_name: 'Deleted Plant', owned_by: @current_user.email)
          @unowned_public_plant = create(:plant, :public, scientific_name: 'Unowned Public Plant', owned_by: 'not_me')
          @unowned_private_plant = create(:plant, :private, scientific_name: 'Unowned Private Plant', owned_by: 'not_me')
          @unowned_draft_plant = create(:plant, :draft, scientific_name: 'Unowned Draft Plant', owned_by: 'not_me')
          @unowned_deleted_plant = create(:plant, :deleted, scientific_name: 'Unowned Deleted Plant', owned_by: 'not_me')
        end
        it 'shows only public records when public' do
          result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: { visibility: 'PUBLIC' })
          plant_result = result['data']['plants']['nodes']

          expect(plant_result.length).to eq 2
          expect(plant_result[0]['scientificName']).to eq('Public Plant') | eq('Unowned Public Plant')
          expect(plant_result[1]['scientificName']).to eq('Public Plant') | eq('Unowned Public Plant')
        end

        it 'shows only private records when private' do
          result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: { visibility: 'PRIVATE' })
          plant_result = result['data']['plants']['nodes']

          expect(plant_result.length).to eq 1
          expect(plant_result[0]['scientificName']).to eq('Private Plant')
        end

        it 'shows only draft records when draft' do
          result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: { visibility: 'DRAFT' })
          plant_result = result['data']['plants']['nodes']

          expect(plant_result.length).to eq 1
          expect(plant_result[0]['scientificName']).to eq('Draft Plant')
        end

        it 'shows only deleted records when deleted' do
          result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: { visibility: 'DELETED' })
          plant_result = result['data']['plants']['nodes']

          expect(plant_result.length).to eq 1
          expect(plant_result[0]['scientificName']).to eq('Deleted Plant')
        end

        it 'show both public and private records when visible' do
          result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: { visibility: 'VISIBLE' })
          plant_result = result['data']['plants']['nodes']

          expect(plant_result.length).to eq 3
          expect(plant_result[0]['scientificName']).to eq('Public Plant') | eq('Unowned Public Plant') | eq('Private Plant')
          expect(plant_result[1]['scientificName']).to eq('Public Plant') | eq('Unowned Public Plant') | eq('Private Plant')
          expect(plant_result[2]['scientificName']).to eq('Public Plant') | eq('Unowned Public Plant') | eq('Private Plant')
        end
      end
      describe 'when user is an admin' do
        before :each do
          @current_user = build(:user, :admin)

          @query_string = <<-GRAPHQL
						query($visibility: Visibility){
							plants(visibility: $visibility){
								nodes{
									id
									scientificName
									ownedBy
								}
							}
						}
          GRAPHQL

          @public_plant = create(:plant, :public, scientific_name: 'Public Plant', owned_by: @current_user.email)
          @private_plant = create(:plant, :private, scientific_name: 'Private Plant', owned_by: @current_user.email)
          @draft_plant = create(:plant, :draft, scientific_name: 'Draft Plant', owned_by: @current_user.email)
          @deleted_plant = create(:plant, :deleted, scientific_name: 'Deleted Plant', owned_by: @current_user.email)
          @unowned_public_plant = create(:plant, :public, scientific_name: 'Unowned Public Plant', owned_by: 'not_me')
          @unowned_private_plant = create(:plant, :private, scientific_name: 'Unowned Private Plant', owned_by: 'not_me')
          @unowned_draft_plant = create(:plant, :draft, scientific_name: 'Unowned Draft Plant', owned_by: 'not_me')
          @unowned_deleted_plant = create(:plant, :deleted, scientific_name: 'Unowned Deleted Plant', owned_by: 'not_me')
        end

        it "allows access to other user's private records" do
          result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: { visibility: 'PRIVATE' })
          plant_result = result['data']['plants']['nodes']

          expect(plant_result.length).to eq 2
          expect(plant_result[0]['scientificName']).to eq('Private Plant').or eq('Unowned Private Plant')
          expect(plant_result[1]['scientificName']).to eq('Private Plant').or eq('Unowned Private Plant')
        end
      end
    end
  end

  describe 'sortDirecton parameter' do
    before :each do
      @query_string = <<-GRAPHQL
				query($sortDirection: SortDirection){
					plants(sortDirection: $sortDirection){
						nodes{
							id
							scientificName
						}
					}
				}
      GRAPHQL

      create(:plant, :public, scientific_name: 'a')
      create(:plant, :public, scientific_name: 'd')
      create(:plant, :public, scientific_name: 'c')
      create(:plant, :public, scientific_name: 'b')
    end

    it 'sorts ascending by scientific_name' do
      result = PlantApiSchema.execute(@query_string, variables: { sortDirection: 'ASC' })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result[0]['scientificName']).to eq 'a'
      expect(plant_result[1]['scientificName']).to eq 'b'
      expect(plant_result[2]['scientificName']).to eq 'c'
      expect(plant_result[3]['scientificName']).to eq 'd'
    end
    it 'sorts descending by scientific_name' do
      result = PlantApiSchema.execute(@query_string, variables: { sortDirection: 'DESC' })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result[0]['scientificName']).to eq 'd'
      expect(plant_result[1]['scientificName']).to eq 'c'
      expect(plant_result[2]['scientificName']).to eq 'b'
      expect(plant_result[3]['scientificName']).to eq 'a'
    end
  end

  describe 'ownedBy filter' do
    before :each do
      @current_user = build(:user, :admin)

      @query_string = <<-GRAPHQL
				query($ownedBy: String){
					plants(ownedBy: $ownedBy, visibility: PRIVATE){
						nodes{
							id
							scientificName
							ownedBy
						}
					}
				}
      GRAPHQL

      create(:plant, :private, owned_by: @current_user.email)
      create(:plant, :private, owned_by: 'not_me')
      create(:plant, :private, owned_by: 'not_me_either')
    end

    it 'does not limit when nil' do
      result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: { ownedBy: nil })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 3
    end

    it 'limits results to the specified user for owned records' do
      result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: { ownedBy: @current_user.email })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 1
      expect(plant_result[0]['ownedBy']).to eq(@current_user.email)
    end

    it 'limits results to the specified user for unowned records' do
      result = PlantApiSchema.execute(@query_string, context: { current_user: @current_user }, variables: { ownedBy: 'not_me' })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 1
      expect(plant_result[0]['ownedBy']).to eq('not_me')
    end
  end

  describe 'scientificName filter' do
    before :each do
      @current_user = build(:user, :admin)

      @query_string = <<-GRAPHQL
				query($scientificName: String){
					plants(scientificName: $scientificName, visibility: PUBLIC){
						nodes{
							id
							scientificName
						}
					}
				}
      GRAPHQL

      create(:plant, :public, scientific_name: 'Happy Man')
      create(:plant, :public, scientific_name: 'Sad Girl')
      create(:plant, :public, scientific_name: 'Mad Girl')
      create(:plant, :public, scientific_name: 'Happy Girl')
      create(:plant, :public, scientific_name: 'Orange Boy')
    end

    it 'does not limit when nil' do
      result = PlantApiSchema.execute(@query_string, variables: { scientificName: nil })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 5
    end

    it 'can return single results' do
      result = PlantApiSchema.execute(@query_string, variables: { scientificName: 'orange' })
      plant_result = result['data']['plants']['nodes']
      expect(plant_result.length).to eq 1
    end

    it 'can return multiple results' do
      result = PlantApiSchema.execute(@query_string, variables: { scientificName: 'girl' })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 3
    end
  end

  describe 'name filter' do
    before :each do
      @current_user = build(:user, :admin)

      @query_string = <<-GRAPHQL
				query($name: String){
					plants(name: $name, visibility: PUBLIC){
						nodes{
							id
              scientificName
              primaryCommonName
              commonNames{
                nodes{
                  name
                  language
                }
              }
						}
					}
				}
      GRAPHQL

      @p_a = create(:plant, :public, scientific_name: 'a')
      create(:common_name, plant: @p_a, primary: true, name: 'happy man')
      @p_b = create(:plant, :public, scientific_name: 'b')
      create(:common_name, plant: @p_b, primary: true, name: 'sad girl')
      @p_c = create(:plant, :public, scientific_name: 'c')
      create(:common_name, plant: @p_c, primary: true, name: 'mad girl')
      @p_d = create(:plant, :public, scientific_name: 'd')
      create(:common_name, plant: @p_d, primary: true, name: 'happy girl')
      @p_e = create(:plant, :public, scientific_name: 'e')
      create(:common_name, plant: @p_e, primary: true, name: 'orange boy')
    end

    it 'does not limit when nil' do
      result = PlantApiSchema.execute(@query_string, variables: { name: nil })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 5
    end

    it 'can return single results' do
      result = PlantApiSchema.execute(@query_string, variables: { name: 'orange' })
      plant_result = result['data']['plants']['nodes']
      expect(plant_result.length).to eq 1
    end

    it 'can return multiple results' do
      result = PlantApiSchema.execute(@query_string, variables: { name: 'girl' })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 3
    end
  end

  describe 'anyName filter' do
    before :each do
      @current_user = build(:user, :admin)

      @query_string = <<-GRAPHQL
				query($anyName: String){
					plants(anyName: $anyName, visibility: PUBLIC){
						nodes{
							id
              scientificName
              primaryCommonName
              commonNames{
                nodes{
                  name
                  language
                }
              }
						}
					}
				}
      GRAPHQL

      @p_a = create(:plant, :public, scientific_name: 'male')
      create(:common_name, plant: @p_a, primary: true, name: 'happy man')
      create(:common_name, plant: @p_a, primary: false, name: 'me')
      @p_b = create(:plant, :public, scientific_name: 'ladies')
      create(:common_name, plant: @p_b, primary: true, name: 'sad girl')
      @p_c = create(:plant, :public, scientific_name: 'ladies')
      create(:common_name, plant: @p_c, primary: true, name: 'mad girl')
      @p_d = create(:plant, :public, scientific_name: 'ladies')
      create(:common_name, plant: @p_d, primary: true, name: 'happy girl')
      @p_e = create(:plant, :public, scientific_name: 'boy')
      create(:common_name, plant: @p_e, primary: true, name: 'blue male')
      @p_f = create(:plant, :public, scientific_name: 'dog')
      create(:common_name, plant: @p_f, primary: true, name: 'rover')
      create(:common_name, plant: @p_f, primary: true, name: 'male dog')
      @p_g = create(:plant, :public, scientific_name: 'dog')
      create(:common_name, plant: @p_g, primary: true, name: 'doggo')
      create(:common_name, plant: @p_g, primary: true, name: 'male dog')
      create(:common_name, plant: @p_g, primary: true, name: 'orange dog')
    end

    it 'does not limit when nil' do
      result = PlantApiSchema.execute(@query_string, variables: { anyName: nil })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 7
    end

    it 'can return single results' do
      result = PlantApiSchema.execute(@query_string, variables: { anyName: 'orange' })
      plant_result = result['data']['plants']['nodes']
      expect(plant_result.length).to eq 1
    end

    it 'can return multiple results' do
      result = PlantApiSchema.execute(@query_string, variables: { anyName: 'girl' })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 3
    end

    it 'returns results from both name and common name' do
      result = PlantApiSchema.execute(@query_string, variables: { anyName: 'male' })
      plant_result = result['data']['plants']['nodes']

      expect(plant_result.length).to eq 4
    end
  end

  describe 'totalCount attribute' do
    it 'counts all available records' do
      query_string = <<-GRAPHQL
			query{
				plants{
					totalCount
				}
			}
      GRAPHQL

      create(:plant, :public, scientific_name: 'plant a')
      create(:plant, :public, scientific_name: 'plant b')

      result = PlantApiSchema.execute(query_string)
      total_count = result['data']['plants']['totalCount']

      expect(total_count).to eq 2
    end

    it 'does not count unavailable records' do
      query_string = <<-GRAPHQL
			query{
				plants{
					totalCount
				}
			}
      GRAPHQL

      create(:plant, :public, scientific_name: 'plant a')
      create(:plant, :private, scientific_name: 'plant b')

      result = PlantApiSchema.execute(query_string)
      total_count = result['data']['plants']['totalCount']

      expect(total_count).to eq 1
    end
  end
end
