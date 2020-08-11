# frozen_string_literal: true

module Mutations
  class UpdateCategory < BaseMutation
    argument :category_id, ID, required: true, loads: Types::CategoryType

    argument :name, String, required: false
    argument :description, String, required: false
    argument :language, String, required: false
    argument :visibility, Types::VisibilityEnum, required: false

    field :category, Types::CategoryType, null: true
    field :errors, [String], null: false

    def authorized?(category:, **_attributes)
      authorize category, :update?
    end

    def resolve(category:, **attributes)
      language = attributes[:language] || I18n.locale

      Mobility.with_locale(language) do
        if category.update(attributes.except(:language))
          {
            category: category,
            errors: []
          }
        else
          {
            category: category,
            errors: category.errors.full_messages
          }
        end
      end
    end
  end
end
