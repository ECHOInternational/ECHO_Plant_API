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
    argument :organization_id, ID,
             required: false,
             description: 'Relay global ID of the organization on whose behalf this category is created. Defaults to the personal organization.'

    field :category, Types::CategoryType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(**_attributes)
      authorize Category, :create?
    end

    def resolve(**attributes)
      language = attributes[:language] || I18n.locale

      org_id_arg = attributes.delete(:organization_id)
      if org_id_arg
        stamp, err = acting_organization_stamp(org_id_arg)
        return { category: nil, errors: [err] } if err

        org_stamp = stamp
      else
        org_stamp = ownership_stamp
      end

      attributes
        .except!(:language)
        .merge!(created_by: context[:current_user].email)
        .merge!(owned_by: context[:current_user].email)
        .merge!(org_stamp)

      Mobility.with_locale(language) do
        category = Category.new(attributes)
        result = category.save
        errors = errors_from_active_record category.errors
        {
          category: result ? category : nil,
          errors: errors
        }
      end
    end
  end
end
