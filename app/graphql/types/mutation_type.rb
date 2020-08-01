module Types
  class MutationType < Types::BaseObject
    field :create_category, mutation: Mutations::CreateCategory, description: "Creates a new plant category"
    field :update_category, mutation: Mutations::UpdateCategory, description: "Updates a plant category"
    field :delete_category, mutation: Mutations::DeleteCategory, description: "Deletes a plant category"
  end
end
