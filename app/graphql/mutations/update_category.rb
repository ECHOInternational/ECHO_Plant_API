# frozen_string_literal: true

module Mutations
  # Modifies editble fields for a Category
  class UpdateCategory < BaseMutation
    argument :category_id, ID, required: true, loads: Types::CategoryType

    argument :name, String, required: false
    argument :description, String, required: false
    argument :language, String, required: false
    argument :visibility, Types::VisibilityEnum, required: false

    field :category, Types::CategoryType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(category:, **_attributes)
      authorize category, :update?
    end

    def resolve(category:, **attributes)
      language = attributes[:language] || I18n.locale

      Mobility.with_locale(language) do
        category.update(attributes.except(:language))
        {
          category: category,
          errors: errors_from_active_record(category.errors)
        }
      end
    end
  end
end
