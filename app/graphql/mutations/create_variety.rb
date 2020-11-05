# frozen_string_literal: true

module Mutations
  # Creates a Plant Variety
  class CreateVariety < BaseMutation
    argument :plant_id, ID,
             required: true,
             description: 'The plant to which this variety belongs',
             loads: Types::PlantType
    argument :name, String,
             required: true,
             description: 'The name of the variety'
    argument :description, String,
             required: false,
             description: 'The translatable description of the variety'
    argument :language, String,
             required: false,
             description: 'Language of the translatable fields supplied'
    argument :visibility, Types::VisibilityEnum,
             required: false,
             description: 'The visibility of the variety'

    field :variety, Types::VarietyType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(**_attributes)
      authorize Variety, :create?
    end

    def resolve(**attributes)
      language = attributes[:language] || I18n.locale

      attributes
        .except!(:language)
        .merge!(created_by: context[:current_user].email)
        .merge!(owned_by: context[:current_user].email)

      Mobility.with_locale(language) do
        variety = Variety.new(attributes)
        result = variety.save
        errors = errors_from_active_record variety.errors
        {
          variety: result ? variety : nil,
          errors: errors
        }
      end
    end
  end
end
