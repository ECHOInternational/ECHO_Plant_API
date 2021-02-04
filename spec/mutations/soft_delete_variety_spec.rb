# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Soft Delete Variety Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:variety) { create(:variety) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: SoftDeleteVarietyInput!){
			softDeleteVariety(input: $input){
				variety {
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
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          varietyId: variety_id
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
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          varietyId: variety_id
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
    let(:variety) { create(:variety, owned_by: current_user.email, created_by: current_user.email, name: 'a name', description: 'a description') }

    context 'when the user does not own the record' do
      let(:variety) { create(:variety, owned_by: 'notme', created_by: 'notme', name: 'a name', description: 'a description') }
      it 'raises an error' do
        @variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            varietyId: @variety_id
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
          variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
          record_id = variety.id
          expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                            input: {
                                              varietyId: variety_id
                                            }
                                          })
          expect(result).to_not include 'errors'
          expect(result).to include 'data'
          expect(result['data']['softDeleteVariety']).to include 'variety'
          expect(result['data']['softDeleteVariety']['variety']['id']).to eq variety_id
          expect(result['data']['softDeleteVariety']['variety']['visibility']).to eq "DELETED"
          expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          variety.reload
          expect(variety.visibility).to eq 'deleted'
        end
      end
      context 'when there is a related specimen' do
        context 'and the specimen is not soft-deleted' do
          let(:specimen) { create(:specimen, plant: variety.plant, variety: variety) }
          context 'without force parameter' do
            it 'returns an error' do
              variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
              record_id = variety.id
              expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(specimen.variety_id).to eq variety.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  varietyId: variety_id
                                                }
                                              })
              expect(result).to include 'data'
              expect(result['data']['softDeleteVariety']).to include 'variety'
              expect(result['data']['softDeleteVariety']['variety']['visibility']).to_not eq "DELETED"
              expect(result['data']['softDeleteVariety']['errors'][0]).to include 'code'
              expect(result['data']['softDeleteVariety']['errors'][0]['code']).to eq 400
              expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            end
          end
          context 'when force parameter is true' do
            it 'soft deletes the record' do
              variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
              record_id = variety.id
              expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(specimen.variety_id).to eq variety.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  varietyId: variety_id,
                                                  force: true
                                                }
                                              })
              expect(result).to_not include 'errors'
              expect(result).to include 'data'
              expect(result['data']['softDeleteVariety']).to include 'variety'
              expect(result['data']['softDeleteVariety']['variety']['id']).to eq variety_id
              expect(result['data']['softDeleteVariety']['variety']['visibility']).to eq "DELETED"
              expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              variety.reload
              expect(variety.visibility).to eq 'deleted'
            end
          end
        end
        context 'and the specimen is soft-deleted' do
          let(:specimen) { create(:specimen, plant: variety.plant, variety: variety, visibility: :deleted) }
          it 'soft deletes the record' do
            variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
            record_id = variety.id
            expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            expect(specimen.variety_id).to eq variety.id
            result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                              input: {
                                                varietyId: variety_id
                                              }
                                            })
            expect(result).to_not include 'errors'
            expect(result).to include 'data'
            expect(result['data']['softDeleteVariety']).to include 'variety'
            expect(result['data']['softDeleteVariety']['variety']['id']).to eq variety_id
            expect(result['data']['softDeleteVariety']['variety']['visibility']).to eq "DELETED"
            expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            variety.reload
            expect(variety.visibility).to eq 'deleted'
          end
        end
        context 'with multiple relationships with different visibility values' do
          let(:deleted_specimen_a) { create(:specimen, plant: variety.plant, variety: variety, visibility: :deleted) }
          let(:deleted_specimen_b) { create(:specimen, plant: variety.plant, variety: variety, visibility: :deleted) }
          let(:private_specimen_a) { create(:specimen, plant: variety.plant, variety: variety, visibility: :private) }
          let(:public_specimen_a) { create(:specimen, plant: variety.plant, variety: variety, visibility: :public) }

          it 'returns multiple errors' do
            # refer to specimens so they are created
            deleted_specimen_a
            deleted_specimen_b
            private_specimen_a
            public_specimen_a

            variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
            record_id = variety.id
            expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                              input: {
                                                varietyId: variety_id
                                              }
                                            })
            expect(result['data']['softDeleteVariety']).to include 'variety'
            expect(result['data']['softDeleteVariety']['variety']['visibility']).to_not eq "DELETED"
            expect(result['data']['softDeleteVariety']['errors'][0]).to include 'code'
            expect(result['data']['softDeleteVariety']['errors'][0]['code']).to eq 400
            expect(result['data']['softDeleteVariety']['errors'][1]).to include 'code'
            expect(result['data']['softDeleteVariety']['errors'][1]['code']).to eq 400
            expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end
  end
end
