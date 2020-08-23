# frozen_string_literal: true

module Types
  # Defines the available mutations for the Plant API
  class MutationType < Types::BaseObject
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
  end
end
