# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :create_category, mutation: Mutations::CreateCategory, description: 'Creates a new plant category'
    field :update_category, mutation: Mutations::UpdateCategory, description: 'Updates a plant category'
    field :delete_category, mutation: Mutations::DeleteCategory, description: 'Deletes a plant category'
    field :create_image, mutation: Mutations::CreateImage, description: 'Creates an image for a given API object'
    field :update_image, mutation: Mutations::UpdateImage, description: "Updates an image's editable metadata"
    field :delete_image, mutation: Mutations::DeleteImage, description: 'Deletes an image'
    field :add_image_attributes_to_image, mutation: Mutations::AddImageAttributesToImage, description: 'Adds image attributes to an image'
    field :remove_image_attributes_from_image, mutation: Mutations::RemoveImageAttributesFromImage, description: 'Removes image attributes from an image'
  end
end
