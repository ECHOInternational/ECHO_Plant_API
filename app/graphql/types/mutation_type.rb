# frozen_string_literal: true

module Types
  # Defines the available mutations for the Plant API
  class MutationType < Types::BaseObject # rubocop:disable Metrics/ClassLength
    field :create_category,
          mutation: Mutations::CreateCategory,
          description: 'Creates a new plant category'
    field :update_category,
          mutation: Mutations::UpdateCategory,
          description: 'Updates a plant category'
    field :delete_category,
          mutation: Mutations::DeleteCategory,
          description: 'Deletes a plant category'
    field :create_image,
          mutation: Mutations::CreateImage,
          description: 'Creates an image for a given API object'
    field :update_image,
          mutation: Mutations::UpdateImage,
          description: "Updates an image's editable metadata"
    field :delete_image,
          mutation: Mutations::DeleteImage,
          description: 'Deletes an image'
    field :add_image_attributes_to_image,
          mutation: Mutations::AddImageAttributesToImage,
          description: 'Adds image attributes to an image'
    field :remove_image_attributes_from_image,
          mutation: Mutations::RemoveImageAttributesFromImage,
          description: 'Removes image attributes from an image'
    field :create_specimen,
          mutation: Mutations::CreateSpecimen,
          description: 'Creates a new specimen'
    field :update_specimen,
          mutation: Mutations::UpdateSpecimen,
          description: 'Updates a specimen'
    field :delete_specimen,
          mutation: Mutations::DeleteSpecimen,
          description: 'Deletes a specimen'
    field :create_location,
          mutation: Mutations::CreateLocation,
          description: 'Creates a new location'
    field :update_location,
          mutation: Mutations::UpdateLocation,
          description: 'Updates a location'
    field :delete_location,
          mutation: Mutations::DeleteLocation,
          description: 'Deletes a location'
    field :delete_life_cycle_event,
          mutation: Mutations::LifeCycleEvents::DeleteLifeCycleEvent,
          description: 'Deletes a life cycle event'
    field :add_acquire_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddAcquireLifeCycleEvent,
          description: 'Adds an acquire life cycle event to a specimen'
    field :update_acquire_event,
          mutation: Mutations::LifeCycleEvents::UpdateAcquireLifeCycleEvent,
          description: 'Updates an acquire life cycle event'
    field :add_thinning_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddThinningLifeCycleEvent,
          description: 'Adds a thinning life cycle event to a specimen'
    field :update_thinning_event,
          mutation: Mutations::LifeCycleEvents::UpdateThinningLifeCycleEvent,
          description: 'Updates a thinning life cycle event'
    field :add_nutrient_deficiency_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddNutrientDeficiencyLifeCycleEvent,
          description: 'Adds a nutrient deficiency life cycle event to a specimen'
    field :update_nutrient_deficiency_event,
          mutation: Mutations::LifeCycleEvents::UpdateNutrientDeficiencyLifeCycleEvent,
          description: 'Updates a nutrient deficiency life cycle event'
    field :add_staking_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddStakingLifeCycleEvent,
          description: 'Adds a Staking life cycle event to a specimen'
    field :update_staking_event,
          mutation: Mutations::LifeCycleEvents::UpdateStakingLifeCycleEvent,
          description: 'Updates a Staking life cycle event'
    field :add_trellising_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddTrellisingLifeCycleEvent,
          description: 'Adds a Trellising life cycle event to a specimen'
    field :update_trellising_event,
          mutation: Mutations::LifeCycleEvents::UpdateTrellisingLifeCycleEvent,
          description: 'Updates a Trellising life cycle event'
    field :add_disease_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddDiseaseLifeCycleEvent,
          description: 'Adds a Disease life cycle event to a specimen'
    field :update_disease_event,
          mutation: Mutations::LifeCycleEvents::UpdateDiseaseLifeCycleEvent,
          description: 'Updates a Disease life cycle event'
    field :add_pest_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddPestLifeCycleEvent,
          description: 'Adds a Pest life cycle event to a specimen'
    field :update_pest_event,
          mutation: Mutations::LifeCycleEvents::UpdatePestLifeCycleEvent,
          description: 'Updates a Pest life cycle event'
    field :add_pruning_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddPruningLifeCycleEvent,
          description: 'Adds a Pruning life cycle event to a specimen'
    field :update_pruning_event,
          mutation: Mutations::LifeCycleEvents::UpdatePruningLifeCycleEvent,
          description: 'Updates a Pruning life cycle event'
    field :add_weed_management_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddWeedManagementLifeCycleEvent,
          description: 'Adds a Weed Management life cycle event to a specimen'
    field :update_weed_management_event,
          mutation: Mutations::LifeCycleEvents::UpdateWeedManagementLifeCycleEvent,
          description: 'Updates a Weed Management life cycle event'
    field :add_cultivating_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddCultivatingLifeCycleEvent,
          description: 'Adds a Cultivating life cycle event to a specimen'
    field :update_cultivating_event,
          mutation: Mutations::LifeCycleEvents::UpdateCultivatingLifeCycleEvent,
          description: 'Updates a Cultivating life cycle event'
    field :add_composting_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddCompostingLifeCycleEvent,
          description: 'Adds a Composting life cycle event to a specimen'
    field :update_composting_event,
          mutation: Mutations::LifeCycleEvents::UpdateCompostingLifeCycleEvent,
          description: 'Updates a Composting life cycle event'
    field :add_mulching_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddMulchingLifeCycleEvent,
          description: 'Adds a Mulching life cycle event to a specimen'
    field :update_mulching_event,
          mutation: Mutations::LifeCycleEvents::UpdateMulchingLifeCycleEvent,
          description: 'Updates a Mulching life cycle event'
    field :add_fertilizing_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddFertilizingLifeCycleEvent,
          description: 'Adds a Fertilizing life cycle event to a specimen'
    field :update_fertilizing_event,
          mutation: Mutations::LifeCycleEvents::UpdateFertilizingLifeCycleEvent,
          description: 'Updates a Fertilizing life cycle event'
    field :add_other_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddOtherLifeCycleEvent,
          description: 'Adds an Other life cycle event to a specimen'
    field :update_other_event,
          mutation: Mutations::LifeCycleEvents::UpdateOtherLifeCycleEvent,
          description: 'Updates an Other life cycle event'
    field :add_end_of_life_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddEndOfLifeLifeCycleEvent,
          description: 'Adds an End Of Life life cycle event to a specimen'
    field :update_end_of_life_event,
          mutation: Mutations::LifeCycleEvents::UpdateEndOfLifeLifeCycleEvent,
          description: 'Updates an End Of Life life cycle event'
    field :add_flowering_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddFloweringLifeCycleEvent,
          description: 'Adds a Flowering life cycle event to a specimen'
    field :update_flowering_event,
          mutation: Mutations::LifeCycleEvents::UpdateFloweringLifeCycleEvent,
          description: 'Updates a Flowering life cycle event'
    field :add_germination_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddGerminationLifeCycleEvent,
          description: 'Adds a Germination life cycle event to a specimen'
    field :update_germination_event,
          mutation: Mutations::LifeCycleEvents::UpdateGerminationLifeCycleEvent,
          description: 'Updates a Germination life cycle event'
    field :add_weather_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddWeatherLifeCycleEvent,
          description: 'Adds a Weather life cycle event to a specimen'
    field :update_weather_event,
          mutation: Mutations::LifeCycleEvents::UpdateWeatherLifeCycleEvent,
          description: 'Updates a Weather life cycle event'
    field :add_soil_preparation_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddSoilPreparationLifeCycleEvent,
          description: 'Adds a Soil Preparation life cycle event to a specimen'
    field :update_soil_preparation_event,
          mutation: Mutations::LifeCycleEvents::UpdateSoilPreparationLifeCycleEvent,
          description: 'Updates a Soil Preparation life cycle event'
    field :add_harvest_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddHarvestLifeCycleEvent,
          description: 'Adds a Harvest life cycle event to a specimen'
    field :update_harvest_event,
          mutation: Mutations::LifeCycleEvents::UpdateHarvestLifeCycleEvent,
          description: 'Updates a Harvest life cycle event'
    field :add_planting_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddPlantingLifeCycleEvent,
          description: 'Adds a Planting life cycle event to a specimen'
    field :update_planting_event,
          mutation: Mutations::LifeCycleEvents::UpdatePlantingLifeCycleEvent,
          description: 'Updates a Planting life cycle event'
    field :add_movement_event_to_specimen,
          mutation: Mutations::LifeCycleEvents::AddMovementLifeCycleEvent,
          description: 'Adds a Movement life cycle event to a specimen'
    field :update_movement_event,
          mutation: Mutations::LifeCycleEvents::UpdateMovementLifeCycleEvent,
          description: 'Updates a Movement life cycle event'
  end
end
