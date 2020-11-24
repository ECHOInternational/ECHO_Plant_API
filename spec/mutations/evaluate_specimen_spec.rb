# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Evaluate Specimen Mutation', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let(:specimen) { create(:specimen, owned_by: current_user.email) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: EvaluateSpecimenInput!){
			evaluateSpecimen(input: $input){
        errors{
          field
          value
          message
          code
        }
				specimen{
          id
          uuid
          successful
          recommended
          savedSeed
          willShareSeed
          willPlantAgain
          notes
          evaluatedAt
        }
			}
		}
    GRAPHQL
  }

  context 'with valid parameters' do
    before :each do
      @specimen_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           specimenId: @specimen_id,
                                           successful: true,
                                           recommended: true,
                                           savedSeed: true,
                                           willShareSeed: false,
                                           willPlantAgain: true,
                                           notes: 'HEY SOME NOTES!'
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'updates a record' do
      success_result = @result['data']['evaluateSpecimen']['specimen']
      expect(success_result['notes']).to eq 'HEY SOME NOTES!'
      expect(success_result['successful']).to eq true
      expect(success_result['recommended']).to eq true
      expect(success_result['savedSeed']).to eq true
      expect(success_result['willShareSeed']).to eq false
      expect(success_result['willPlantAgain']).to eq true
      expect(success_result['evaluatedAt']).to be_a(String)
      expect(success_result['id']).to eq @specimen_id

      updated_event = Specimen.find success_result['uuid']
      expect(updated_event).to_not be nil
      expect(updated_event.notes).to eq 'HEY SOME NOTES!'
      expect(updated_event.successful?).to eq true
      expect(updated_event.recommended?).to eq true
      expect(updated_event.saved_seed?).to eq true
      expect(updated_event.will_share_seed?).to eq false
      expect(updated_event.will_plant_again?).to eq true
      expect(updated_event.evaluated_at).to be_a(ActiveSupport::TimeWithZone)
    end
  end
  describe 'required parameters' do
    it 'returns errors if the successful value is nil' do
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           specimenId: @specimen_id,
                                           successful: nil,
                                           recommended: true,
                                           savedSeed: true,
                                           willShareSeed: false,
                                           willPlantAgain: true
                                         }
                                       })
      expect(@result).to include 'errors'
      expect(@result).to_not include 'data'
    end
    it 'returns errors if the recommended value is nil' do
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           specimenId: @specimen_id,
                                           successful: true,
                                           recommended: nil,
                                           savedSeed: true,
                                           willShareSeed: false,
                                           willPlantAgain: true
                                         }
                                       })
      expect(@result).to include 'errors'
      expect(@result).to_not include 'data'
    end
    it 'returns errors if the savedSeed value is nil' do
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           specimenId: @specimen_id,
                                           successful: true,
                                           recommended: true,
                                           savedSeed: nil,
                                           willShareSeed: false,
                                           willPlantAgain: true
                                         }
                                       })
      expect(@result).to include 'errors'
      expect(@result).to_not include 'data'
    end
    it 'returns errors if the willShareSeed value is nil' do
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           specimenId: @specimen_id,
                                           successful: true,
                                           recommended: true,
                                           savedSeed: true,
                                           willShareSeed: nil,
                                           willPlantAgain: true
                                         }
                                       })
      expect(@result).to include 'errors'
      expect(@result).to_not include 'data'
    end
    it 'returns errors if the willPlantAgain value is nil' do
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           specimenId: @specimen_id,
                                           successful: true,
                                           recommended: true,
                                           savedSeed: true,
                                           willShareSeed: false,
                                           willPlantAgain: nil
                                         }
                                       })
      expect(@result).to include 'errors'
      expect(@result).to_not include 'data'
    end
  end
end
