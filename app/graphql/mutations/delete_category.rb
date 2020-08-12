# frozen_string_literal: true

module Mutations
  # Deletes a Category
  class DeleteCategory < BaseMutation
    argument :category_id, ID,
             description: 'The category to be deleted',
             required: true,
             loads: Types::CategoryType

    field :category_id, ID, null: true
    field :errors, [String], null: false

    def authorized?(category:, **_attributes)
      authorize category, :destroy?
    end

    def resolve(category:, **_attributes)
      id = category.id
      if category.destroy
        {
          category_id: id,
          errors: []
        }
      else
        {
          category_id: nil,
          errors: category.errors.full_messages
        }
      end
    end
  end
end
