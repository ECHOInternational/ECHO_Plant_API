# frozen_string_literal: true

module Mutations
  # Creates a Plant Category
  class CreateCategory < BaseMutation
    argument :name, String,
             required: true,
             description: 'The translatable name of the category'
    argument :description, String,
             required: false,
             description: 'The translatable description of the category'
    argument :language, String,
             required: false,
             description: 'Language of the translatable fields supplied'
    argument :visibility, Types::VisibilityEnum,
             required: false,
             description: 'The visibility of the category'

    field :category, Types::CategoryType, null: true
    field :errors, [String], null: false

    def authorized?(**_attributes)
      authorize Category, :create?
    end

    def resolve(**attributes)
      language = attributes[:language] || I18n.locale

      attributes
        .except!(:language)
        .merge!(created_by: context[:current_user].email)
        .merge!(owned_by: context[:current_user].email)

      Mobility.with_locale(language) do
        category = Category.new(attributes)
        if category.save
          {
            category: category,
            errors: []
          }
        else
          {
            category: nil,
            errors: category.errors.full_messages
          }
        end
      end
    end
  end
end
