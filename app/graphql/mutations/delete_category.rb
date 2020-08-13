# frozen_string_literal: true

module Mutations
  # Deletes a Category
  class DeleteCategory < BaseMutation
    argument :category_id, ID,
             description: 'The category to be deleted',
             required: true,
             loads: Types::CategoryType

    field :category_id, ID, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(category:, **_attributes)
      authorize category, :destroy?
    end

    def resolve(category:, **_attributes)
      id = PlantApiSchema.id_from_object(category, Category, {})
      result = category.destroy
      errors = errors_from_active_record category.errors
      {
        category_id: result.destroyed? ? id : nil,
        errors: errors
      }
    end
  end
end
