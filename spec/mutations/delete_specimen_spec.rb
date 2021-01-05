# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Delete Specimen Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:specimen) { create(:specimen) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: DeleteSpecimenInput!){
			deleteSpecimen(input: $input){
				specimenId
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
      specimen_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          specimenId: specimen_id
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
      specimen_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          specimenId: specimen_id
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
    let(:specimen) { create(:specimen, owned_by: current_user.email, created_by: current_user.email, name: 'a name') }

    context 'when the user does not own the record' do
      let(:specimen) { create(:specimen, owned_by: 'notme', created_by: 'notme', name: 'a name') }
      it 'raises an error' do
        @specimen_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            specimenId: @specimen_id
                                          }
                                        })
        expect(result['data']).to be_nil
        expect(result['errors']).to_not be_nil
        expect(result['errors'].count).to eq 1
        expect(result['errors'][0]['extensions']['code']).to eq 403
      end
    end
    context 'when user owns the record' do
      it 'deletes the record' do
        specimen_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
        record_id = specimen.id
        expect { Specimen.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            specimenId: specimen_id
                                          }
                                        })
        expect(result).to_not include 'errors'
        expect(result).to include 'data'
        expect(result['data']['deleteSpecimen']).to include 'specimenId'
        expect(result['data']['deleteSpecimen']['specimenId']).to eq specimen_id
        expect { Specimen.find record_id }.to raise_error(ActiveRecord::RecordNotFound)
      end
      context 'when there are related life cycle events' do
        let(:acquire_event) { create(:acquire_event, specimen: specimen) }
        let(:planting_event) { create(:planting_event, specimen: specimen) }
        it 'deletes related life cycle events' do
          specimen_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
          record_id = specimen.id
          expect { Specimen.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          expect(planting_event.specimen_id).to eq specimen.id
          expect(acquire_event.specimen_id).to eq specimen.id
          planting_event_id = planting_event.id
          acquire_event_id = acquire_event.id
          expect { LifeCycleEvent.find planting_event_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          expect { LifeCycleEvent.find acquire_event_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                            input: {
                                              specimenId: specimen_id
                                            }
                                          })
          expect(result).to_not include 'errors'
          expect(result).to include 'data'
          expect(result['data']['deleteSpecimen']).to include 'specimenId'
          expect(result['data']['deleteSpecimen']['specimenId']).to eq specimen_id
          expect { Specimen.find record_id }.to raise_error(ActiveRecord::RecordNotFound)
          expect { LifeCycleEvent.find planting_event_id }.to raise_error(ActiveRecord::RecordNotFound)
          expect { LifeCycleEvent.find acquire_event_id }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end
  end
end
