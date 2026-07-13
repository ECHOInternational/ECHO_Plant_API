# frozen_string_literal: true

require 'rails_helper'

# Contract: all 22 addXxxEventToSpecimen mutations and a representative
# sample of updateXxxEvent mutations, plus deleteLifeCycleEvent.
# Source documents extracted verbatim from:
#   app/store/SeedTrialReports/action.js
#
# Events are added by a trust-level-2 user (the mobile app default).
# The app only requires: the event object sub-fields it reads, clientMutationId,
# and no GraphQL top-level errors.
RSpec.describe 'Mobile lifecycle events contract', type: :graphql_mutation do
  let(:user) { build(:user, :readwrite) }
  let(:plant) { create(:plant, :private, owned_by: user.email, created_by: user.email) }
  let(:specimen) do
    create(:specimen, :private, plant: plant,
                                owned_by: user.email, created_by: user.email)
  end
  let(:location) { create(:location, owned_by: user.email, created_by: user.email) }

  def specimen_gid
    PlantApiSchema.id_from_object(specimen, Specimen, {})
  end

  def location_gid
    PlantApiSchema.id_from_object(location, Location, {})
  end

  shared_examples 'a successful event mutation' do |field_name|
    it "returns no errors and the #{field_name} sub-object" do
      expect(result['errors']).to be_nil
      event_result = result.dig('data', field_name)
      expect(event_result).to be_present
    end
  end

  # ---------------------------------------------------------------
  # Helper: common base variables
  # ---------------------------------------------------------------
  let(:base_variables) do
    {
      specimenId: specimen_gid,
      datetime: '2024-06-15T08:00:00Z',
      notes: 'Mobile test note'
    }
  end

  # =================================================================
  # ADD mutations (22 total)
  # =================================================================

  # -----------------------------------------------------------------
  # 1. addAcquireEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addAcquireEventToSpecimen (action.js addAcquireToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddAcquireLifeCycleEventInput!) {
          addAcquireEventToSpecimen(input: $input) {
            acquireEvent {
              accession
              condition
              datetime
              id
            }
            clientMutationId
            errors {
              message
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: base_variables.merge(condition: 'GOOD', source: 'ECHO Asia', accession: 'ACC-001')
        }
      )
    end

    it 'creates the event and returns id, condition, datetime, accession' do
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'addAcquireEventToSpecimen', 'acquireEvent')
      expect(ev['id']).to be_present
      expect(ev['condition']).to eq('GOOD')
      expect(ev['accession']).to eq('ACC-001')
      expect(ev['datetime']).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 2. addPlantingEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addPlantingEventToSpecimen (action.js addPlantingToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddPlantingLifeCycleEventInput!) {
          addPlantingEventToSpecimen(input: $input) {
            plantingEvent {
              id
              datetime
              location {
                latitude
                longitude
                name
                soilQuality
                slope
                irrigated
              }
            }
            clientMutationId
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: base_variables.merge(locationId: location_gid)
        }
      )
    end

    it 'creates planting event with nested location fields' do
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'addPlantingEventToSpecimen', 'plantingEvent')
      expect(ev['id']).to be_present
      loc = ev['location']
      %w[latitude longitude name soilQuality slope irrigated].each do |f|
        expect(loc).to have_key(f), "expected location field '#{f}'"
      end
    end
  end

  # -----------------------------------------------------------------
  # 3. addSoilPreparationEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addSoilPreparationEventToSpecimen (action.js addSoilPreparationToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddSoilPreparationLifeCycleEventInput!) {
          addSoilPreparationEventToSpecimen(input: $input) {
            soilPreparationEvent {
              id
              datetime
              notes
              soilPreparation
              specimen {
                id
                name
              }
            }
            clientMutationId
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: base_variables.merge(soilPreparation: 'FULL_TILL')
        }
      )
    end

    it 'creates event and returns soilPreparation and specimen' do
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'addSoilPreparationEventToSpecimen', 'soilPreparationEvent')
      expect(ev['id']).to be_present
      expect(ev['soilPreparation']).to eq('FULL_TILL')
      expect(ev.dig('specimen', 'id')).to eq(specimen_gid)
    end
  end

  # -----------------------------------------------------------------
  # 4. addCultivatingEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addCultivatingEventToSpecimen (action.js addCultivatingToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddCultivatingLifeCycleEventInput!) {
          addCultivatingEventToSpecimen(input: $input) {
            clientMutationId
            cultivatingEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event with id, datetime, notes' do
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'addCultivatingEventToSpecimen', 'cultivatingEvent')
      expect(ev['id']).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 5. addCompostingEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addCompostingEventToSpecimen (action.js addCompostingToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddCompostingLifeCycleEventInput!) {
          addCompostingEventToSpecimen(input: $input) {
            clientMutationId
            compostingEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'addCompostingEventToSpecimen', 'compostingEvent')
      expect(ev['id']).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 6. addDiseaseEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addDiseaseEventToSpecimen (action.js addDiseaseToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddDiseaseLifeCycleEventInput!) {
          addDiseaseEventToSpecimen(input: $input) {
            clientMutationId
            diseaseEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addDiseaseEventToSpecimen', 'diseaseEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 7. addFertilizingEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addFertilizingEventToSpecimen (action.js addFertilizingToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddFertilizingLifeCycleEventInput!) {
          addFertilizingEventToSpecimen(input: $input) {
            clientMutationId
            fertilizingEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addFertilizingEventToSpecimen', 'fertilizingEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 8. addFloweringEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addFloweringEventToSpecimen (action.js addFloweringToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddFloweringLifeCycleEventInput!) {
          addFloweringEventToSpecimen(input: $input) {
            clientMutationId
            floweringEvent {
              datetime
              id
              notes
              percent
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: base_variables.merge(percent: 60)
        }
      )
    end

    it 'creates event with percent field' do
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'addFloweringEventToSpecimen', 'floweringEvent')
      expect(ev['id']).to be_present
      expect(ev['percent']).to eq(60)
    end
  end

  # -----------------------------------------------------------------
  # 9. addGerminationEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addGerminationEventToSpecimen (action.js addGerminationToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddGerminationLifeCycleEventInput!) {
          addGerminationEventToSpecimen(input: $input) {
            clientMutationId
            germinationEvent {
              datetime
              id
              notes
              percent
              quality
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: base_variables.merge(percent: 80, quality: 7)
        }
      )
    end

    it 'creates event with percent and quality' do
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'addGerminationEventToSpecimen', 'germinationEvent')
      expect(ev['id']).to be_present
      expect(ev['percent']).to eq(80)
      expect(ev['quality']).to eq(7)
    end
  end

  # -----------------------------------------------------------------
  # 10. addHarvestEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addHarvestEventToSpecimen (action.js addHarvestToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddHarvestLifeCycleEventInput!) {
          addHarvestEventToSpecimen(input: $input) {
            clientMutationId
            harvestEvent {
              datetime
              id
              notes
              quality
              quantity
              unit
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: base_variables.merge(quantity: 12.5, unit: 'WEIGHT', quality: 9)
        }
      )
    end

    it 'creates event with quantity, unit, quality' do
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'addHarvestEventToSpecimen', 'harvestEvent')
      expect(ev['id']).to be_present
      expect(ev['quantity']).to eq(12.5)
      expect(ev['unit']).to eq('WEIGHT')
      expect(ev['quality']).to eq(9)
    end
  end

  # -----------------------------------------------------------------
  # 11. addMovementEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addMovementEventToSpecimen (action.js addMovementToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddMovementLifeCycleEventInput!) {
          addMovementEventToSpecimen(input: $input) {
            clientMutationId
            movementEvent {
              datetime
              id
              notes
              quantity
              unit
              inRowSpacing
              betweenRowSpacing
              location {
                id
                name
              }
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: base_variables.merge(
            locationId: location_gid,
            quantity: 20.0,
            unit: 'COUNT',
            inRowSpacing: 25,
            betweenRowSpacing: 40
          )
        }
      )
    end

    it 'creates event with location, quantity, unit, and spacing' do
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'addMovementEventToSpecimen', 'movementEvent')
      expect(ev['id']).to be_present
      expect(ev['quantity']).to eq(20.0)
      expect(ev['unit']).to eq('COUNT')
      expect(ev['inRowSpacing']).to eq(25)
      expect(ev['betweenRowSpacing']).to eq(40)
      expect(ev.dig('location', 'id')).to eq(location_gid)
      expect(ev.dig('location', 'name')).to be_a(String)
    end
  end

  # -----------------------------------------------------------------
  # 12. addMulchingEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addMulchingEventToSpecimen (action.js addMulchingToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddMulchingLifeCycleEventInput!) {
          addMulchingEventToSpecimen(input: $input) {
            clientMutationId
            mulchingEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addMulchingEventToSpecimen', 'mulchingEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 13. addNutrientDeficiencyEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addNutrientDeficiencyEventToSpecimen (action.js addNutrientDeficiencyToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddNutrientDeficiencyLifeCycleEventInput!) {
          addNutrientDeficiencyEventToSpecimen(input: $input) {
            clientMutationId
            nutrientDeficiencyEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addNutrientDeficiencyEventToSpecimen', 'nutrientDeficiencyEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 14. addOtherEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addOtherEventToSpecimen (action.js addOtherLifeCycleToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddOtherLifeCycleEventInput!) {
          addOtherEventToSpecimen(input: $input) {
            clientMutationId
            otherEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addOtherEventToSpecimen', 'otherEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 15. addPestEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addPestEventToSpecimen (action.js addPestToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddPestLifeCycleEventInput!) {
          addPestEventToSpecimen(input: $input) {
            clientMutationId
            pestEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addPestEventToSpecimen', 'pestEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 16. addPruningEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addPruningEventToSpecimen (action.js addPruningToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddPruningLifeCycleEventInput!) {
          addPruningEventToSpecimen(input: $input) {
            clientMutationId
            pruningEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addPruningEventToSpecimen', 'pruningEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 17. addStakingEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addStakingEventToSpecimen (action.js addStakingToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddStakingLifeCycleEventInput!) {
          addStakingEventToSpecimen(input: $input) {
            clientMutationId
            stakingEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addStakingEventToSpecimen', 'stakingEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 18. addThinningEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addThinningEventToSpecimen (action.js addThiningToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddThinningLifeCycleEventInput!) {
          addThinningEventToSpecimen(input: $input) {
            clientMutationId
            thinningEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addThinningEventToSpecimen', 'thinningEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 19. addTrellisingEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addTrellisingEventToSpecimen (action.js addTrellisingToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddTrellisingLifeCycleEventInput!) {
          addTrellisingEventToSpecimen(input: $input) {
            clientMutationId
            trellisingEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addTrellisingEventToSpecimen', 'trellisingEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 20. addWeatherEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addWeatherEventToSpecimen (action.js addWeatherToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddWeatherLifeCycleEventInput!) {
          addWeatherEventToSpecimen(input: $input) {
            clientMutationId
            weatherEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addWeatherEventToSpecimen', 'weatherEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 21. addWeedManagementEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addWeedManagementEventToSpecimen (action.js addWeedManagementToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddWeedManagementLifeCycleEventInput!) {
          addWeedManagementEventToSpecimen(input: $input) {
            clientMutationId
            weedManagementEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addWeedManagementEventToSpecimen', 'weedManagementEvent', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # 22. addEndOfLifeEventToSpecimen
  # -----------------------------------------------------------------
  describe 'addEndOfLifeEventToSpecimen (action.js addEndOfLifeToSeedTrialReport)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: AddEndOfLifeLifeCycleEventInput!) {
          addEndOfLifeEventToSpecimen(input: $input) {
            clientMutationId
            endOfLifeEvent {
              datetime
              id
              notes
            }
          }
        }
      GRAPHQL
    end

    let(:result) do
      PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: base_variables }
      )
    end

    it 'creates event and returns id' do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'addEndOfLifeEventToSpecimen', 'endOfLifeEvent', 'id')).to be_present
    end
  end

  # =================================================================
  # UPDATE mutations (representative sample of 5)
  # =================================================================

  # -----------------------------------------------------------------
  # updateHarvestEvent (with quantity, unit, quality)
  # -----------------------------------------------------------------
  describe 'updateHarvestEvent (action.js updateHarvestToSeedTrialReport)' do
    let(:event) do
      create(:harvest_event, specimen: specimen, quantity: 1.0, unit: 'weight', quality: 5)
    end

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdateHarvestLifeCycleEventInput!) {
          updateHarvestEvent(input: $input) {
            clientMutationId
            harvestEvent {
              datetime
              id
              notes
              quality
              quantity
              unit
            }
          }
        }
      GRAPHQL
    end

    it 'updates quantity, unit, quality and returns them' do
      event_gid = PlantApiSchema.id_from_object(event, HarvestEvent, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            lifeCycleEventId: event_gid,
            quantity: 99.9,
            unit: 'COUNT',
            quality: 10
          }
        }
      )
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'updateHarvestEvent', 'harvestEvent')
      expect(ev['id']).to eq(event_gid)
      expect(ev['quantity']).to eq(99.9)
      expect(ev['unit']).to eq('COUNT')
      expect(ev['quality']).to eq(10)
    end
  end

  # -----------------------------------------------------------------
  # updateMovementEvent (with location + spacing)
  # -----------------------------------------------------------------
  describe 'updateMovementEvent (action.js updateMovementToSeedTrialReport)' do
    let(:loc2) { create(:location, owned_by: user.email, created_by: user.email) }
    let(:event) do
      create(:movement_event, specimen: specimen, location: location,
                              quantity: 5.0, unit: 'count',
                              between_row_spacing: 10, in_row_spacing: 10)
    end

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdateMovementLifeCycleEventInput!) {
          updateMovementEvent(input: $input) {
            clientMutationId
            movementEvent {
              datetime
              id
              notes
              quantity
              unit
              inRowSpacing
              betweenRowSpacing
              location {
                id
                name
              }
            }
          }
        }
      GRAPHQL
    end

    it 'updates location and spacing and returns them' do
      event_gid = PlantApiSchema.id_from_object(event, MovementEvent, {})
      loc2_gid  = PlantApiSchema.id_from_object(loc2, Location, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            lifeCycleEventId: event_gid,
            locationId: loc2_gid,
            inRowSpacing: 50,
            betweenRowSpacing: 60
          }
        }
      )
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'updateMovementEvent', 'movementEvent')
      expect(ev['id']).to eq(event_gid)
      expect(ev['inRowSpacing']).to eq(50)
      expect(ev['betweenRowSpacing']).to eq(60)
      expect(ev.dig('location', 'id')).to eq(loc2_gid)
    end
  end

  # -----------------------------------------------------------------
  # updateAcquireEvent
  # -----------------------------------------------------------------
  describe 'updateAcquireEvent (action.js updateAcquireToSeedTrialReport)' do
    let(:event) do
      create(:acquire_event, specimen: specimen, condition: 'poor', source: 'Other', accession: 'ACC-OLD')
    end

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdateAcquireLifeCycleEventInput!) {
          updateAcquireEvent(input: $input) {
            acquireEvent {
              accession
              condition
              datetime
              id
            }
            clientMutationId
            errors {
              message
            }
          }
        }
      GRAPHQL
    end

    it 'updates condition and accession and returns them' do
      event_gid = PlantApiSchema.id_from_object(event, AcquireEvent, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            lifeCycleEventId: event_gid,
            condition: 'GOOD',
            accession: 'ACC-NEW'
          }
        }
      )
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'updateAcquireEvent', 'acquireEvent')
      expect(ev['id']).to eq(event_gid)
      expect(ev['condition']).to eq('GOOD')
      expect(ev['accession']).to eq('ACC-NEW')
    end
  end

  # -----------------------------------------------------------------
  # updateFloweringEvent (with percent)
  # -----------------------------------------------------------------
  describe 'updateFloweringEvent (action.js updateFloweringToSeedTrialReport)' do
    let(:event) { create(:flowering_event, specimen: specimen, percent: 10) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdateFloweringLifeCycleEventInput!) {
          updateFloweringEvent(input: $input) {
            clientMutationId
            floweringEvent {
              datetime
              id
              notes
              percent
            }
          }
        }
      GRAPHQL
    end

    it 'updates percent and returns it' do
      event_gid = PlantApiSchema.id_from_object(event, FloweringEvent, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: { lifeCycleEventId: event_gid, percent: 75 }
        }
      )
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'updateFloweringEvent', 'floweringEvent')
      expect(ev['percent']).to eq(75)
    end
  end

  # -----------------------------------------------------------------
  # updateGerminationEvent (with percent + quality)
  # -----------------------------------------------------------------
  describe 'updateGerminationEvent (action.js updateGerminationToSeedTrialReport)' do
    let(:event) { create(:germination_event, specimen: specimen, percent: 20, quality: 3) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdateGerminationLifeCycleEventInput!) {
          updateGerminationEvent(input: $input) {
            clientMutationId
            germinationEvent {
              datetime
              id
              notes
              percent
              quality
            }
          }
        }
      GRAPHQL
    end

    it 'updates percent and quality and returns them' do
      event_gid = PlantApiSchema.id_from_object(event, GerminationEvent, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: { lifeCycleEventId: event_gid, percent: 90, quality: 8 }
        }
      )
      expect(result['errors']).to be_nil
      ev = result.dig('data', 'updateGerminationEvent', 'germinationEvent')
      expect(ev['percent']).to eq(90)
      expect(ev['quality']).to eq(8)
    end
  end

  # =================================================================
  # deleteLifeCycleEvent
  # =================================================================
  describe 'deleteLifeCycleEvent (action.js deleteLifeCycleEventsFromSpecimen)' do
    let(:event) { create(:harvest_event, specimen: specimen, quantity: 1.0, unit: 'weight', quality: 5) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: DeleteLifeCycleEventInput!) {
          deleteLifeCycleEvent(input: $input) {
            clientMutationId
            lifeCycleEventId
          }
        }
      GRAPHQL
    end

    it 'marks the event as deleted and returns lifeCycleEventId' do
      event_gid = PlantApiSchema.id_from_object(event, HarvestEvent, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: { lifeCycleEventId: event_gid }
        }
      )
      expect(result['errors']).to be_nil
      payload = result.dig('data', 'deleteLifeCycleEvent')
      expect(payload['lifeCycleEventId']).to be_present
      event.reload
      expect(event.deleted).to be true
    end
  end
end
