module Mutations
  class CreateCategory < BaseMutation
    argument :name, String, required: true
    argument :description, String, required: false
    argument :language, String, required: false
    argument :visibility, Types::VisibilityEnum, required: false

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
