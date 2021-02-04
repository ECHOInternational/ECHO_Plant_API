# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Soft Delete Plant Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:plant) { create(:plant) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: SoftDeletePlantInput!){
			softDeletePlant(input: $input){
				plant {
          id
          visibility
        }
				errors {
          field
          value
          message
          code
        }
			}
		}
    GRAPHQL
  }

  context 'when user is not authenticated' do
    let(:current_user) { nil }
    it 'returns an error when called' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          plantId: plant_id
                                        }
                                      })
      expect(result['data']).to be_nil
      expect(result['errors']).to_not be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 401
    end
  end

  context 'when user is read only' do
    let(:current_user) { build(:user, :readonly) }
    it 'returns an error when called' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          plantId: plant_id
                                        }
                                      })
      expect(result['data']).to be_nil
      expect(result['errors']).to_not be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 403
    end
  end

  context 'when user is not an admin' do
    let(:current_user) { build(:user, :readwrite) }
    let(:plant) { create(:plant, owned_by: current_user.email, created_by: current_user.email, description: 'a description') }

    context 'when the user does not own the record' do
      let(:plant) { create(:plant, owned_by: 'notme', created_by: 'notme', description: 'a description') }
      it 'raises an error' do
        @plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            plantId: @plant_id
                                          }
                                        })
        expect(result['data']).to be_nil
        expect(result['errors']).to_not be_nil
        expect(result['errors'].count).to eq 1
        expect(result['errors'][0]['extensions']['code']).to eq 403
      end
    end
    context 'when user owns the record' do
      context 'with no related records' do
        it 'soft deletes the record' do
          plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
          record_id = plant.id
          expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                            input: {
                                              plantId: plant_id
                                            }
                                          })
          expect(result).to_not include 'errors'
          expect(result).to include 'data'
          expect(result['data']['softDeletePlant']).to include 'plant'
          expect(result['data']['softDeletePlant']['plant']['id']).to eq plant_id
          expect(result['data']['softDeletePlant']['plant']['visibility']).to eq "DELETED"
          expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          plant.reload
          expect(plant.visibility).to eq 'deleted'
        end
      end
      context 'when there is a related variety' do
        context 'and the specimen is not soft-delted' do
          let(:variety) { create(:variety, plant: plant)}
          context 'without force parameter' do
            it 'returns an error' do
              plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
              record_id = plant.id
              expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(variety.plant_id).to eq plant.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  plantId: plant_id
                                                }
                                              })
              expect(result).to include 'data'
              expect(result['data']['softDeletePlant']).to include 'plant'
              expect(result['data']['softDeletePlant']['plant']['visibility']).to_not eq "DELETED"
              expect(result['data']['softDeletePlant']['errors'][0]).to include 'code'
              expect(result['data']['softDeletePlant']['errors'][0]['code']).to eq 400
              expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            end
          end
          context 'when force parameter is true' do
            it 'soft deletes the record' do
              plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
              record_id = plant.id
              expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(variety.plant_id).to eq plant.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  plantId: plant_id,
                                                  force: true
                                                }
                                              })
              expect(result).to_not include 'errors'
              expect(result).to include 'data'
              expect(result['data']['softDeletePlant']).to include 'plant'
              expect(result['data']['softDeletePlant']['plant']['id']).to eq plant_id
              expect(result['data']['softDeletePlant']['plant']['visibility']).to eq "DELETED"
              expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              plant.reload
              expect(plant.visibility).to eq 'deleted'
            end
          end
        end
        context 'and the specimen is soft-deleted' do
          let(:variety) { create(:variety, plant: plant, visibility: :deleted)}
          it "soft deletes the record" do
            plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
            record_id = plant.id
            expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            expect(variety.plant_id).to eq plant.id
            result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                              input: {
                                                plantId: plant_id
                                              }
                                            })
            expect(result).to_not include 'errors'
            expect(result).to include 'data'
            expect(result['data']['softDeletePlant']).to include 'plant'
            expect(result['data']['softDeletePlant']['plant']['id']).to eq plant_id
            expect(result['data']['softDeletePlant']['plant']['visibility']).to eq "DELETED"
            expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            plant.reload
            expect(plant.visibility).to eq 'deleted'
          end
        end
      end
      context 'when there is a related specimen' do
        context 'and the specimen is not soft-deleted' do
          let(:specimen) { create(:specimen, plant: plant) }
          context 'without force parameter' do
            it 'returns an error' do
              plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
              record_id = plant.id
              expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(specimen.plant_id).to eq plant.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  plantId: plant_id
                                                }
                                              })
              expect(result).to include 'data'
              expect(result['data']['softDeletePlant']).to include 'plant'
              expect(result['data']['softDeletePlant']['plant']['visibility']).to_not eq "DELETED"
              expect(result['data']['softDeletePlant']['errors'][0]).to include 'code'
              expect(result['data']['softDeletePlant']['errors'][0]['code']).to eq 400
              expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            end
          end
          context 'when force parameter is true' do
            it 'soft deletes the record' do
              plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
              record_id = plant.id
              expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(specimen.plant_id).to eq plant.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  plantId: plant_id,
                                                  force: true
                                                }
                                              })
              expect(result).to_not include 'errors'
              expect(result).to include 'data'
              expect(result['data']['softDeletePlant']).to include 'plant'
              expect(result['data']['softDeletePlant']['plant']['id']).to eq plant_id
              expect(result['data']['softDeletePlant']['plant']['visibility']).to eq "DELETED"
              expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              plant.reload
              expect(plant.visibility).to eq 'deleted'
            end
          end
        end
        context 'and the specimen is soft-deleted' do
          let(:specimen) { create(:specimen, plant: plant, visibility: :deleted) }
          it 'soft deletes the record' do
            plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
            record_id = plant.id
            expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            expect(specimen.plant_id).to eq plant.id
            result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                              input: {
                                                plantId: plant_id
                                              }
                                            })
            expect(result).to_not include 'errors'
            expect(result).to include 'data'
            expect(result['data']['softDeletePlant']).to include 'plant'
            expect(result['data']['softDeletePlant']['plant']['id']).to eq plant_id
            expect(result['data']['softDeletePlant']['plant']['visibility']).to eq "DELETED"
            expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            plant.reload
            expect(plant.visibility).to eq 'deleted'
          end
        end
        context 'with multiple relationships with different visibility values' do
          let(:deleted_specimen_a) { create(:specimen, plant: plant, visibility: :deleted) }
          let(:deleted_variety_b) { create(:variety, plant: plant, visibility: :deleted) }
          let(:private_specimen_c) { create(:specimen, plant: plant, visibility: :private) }
          let(:public_variety_d) { create(:variety, plant: plant, visibility: :public) }

          it 'returns multiple errors' do
            # refer to specimens so they are created
            deleted_specimen_a
            deleted_variety_b
            private_specimen_c
            public_variety_d

            plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
            record_id = plant.id
            expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                              input: {
                                                plantId: plant_id
                                              }
                                            })
            expect(result['data']['softDeletePlant']).to include 'plant'
            expect(result['data']['softDeletePlant']['plant']['visibility']).to_not eq "DELETED"
            expect(result['data']['softDeletePlant']['errors'][0]).to include 'code'
            expect(result['data']['softDeletePlant']['errors'][0]['code']).to eq 400
            expect(result['data']['softDeletePlant']['errors'][1]).to include 'code'
            expect(result['data']['softDeletePlant']['errors'][1]['code']).to eq 400
            expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end
  end
end
