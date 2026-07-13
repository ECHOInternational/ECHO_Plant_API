# frozen_string_literal: true

module Mutations
  # Creates a Plant Plant
  class CreatePlant < BaseMutation
    argument :primary_common_name, String,
             required: true,
             description: "The translatable name of the plant. This will be stored as the plant's primary common name"
    argument :description, String,
             required: false,
             description: 'The translatable description of the plant'
    argument :scientific_name, String,
             required: false,
             description: 'The scientific name of the plant'
    argument :family_names, String,
             required: false,
             description: 'The family names of the plant'
    argument :language, String,
             required: false,
             description: 'Language of the translatable fields supplied'
    argument :visibility, Types::VisibilityEnum,
             required: false,
             description: 'The visibility of the plant'

    include Mutations::Concerns::PlantEditableArguments
    include Mutations::Concerns::RangeLiteralValidation

    field :plant, Types::PlantType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(**_attributes)
      authorize Plant, :create?
    end

    def resolve(**attributes) # rubocop:disable Metrics/AbcSize
      range_errors = validate_range_literals(attributes)
      return { plant: nil, errors: range_errors } if range_errors.any?

      language = attributes[:language] || I18n.locale
      primary_common_name = attributes[:primary_common_name]

      attributes
        .except!(:language)
        .except!(:primary_common_name)
        .merge!(created_by: context[:current_user].email)
        .merge!(owned_by: context[:current_user].email)
        .merge!(ownership_stamp)

      Mobility.with_locale(language) do
        plant = Plant.new(attributes)
        plant.common_names.build(name: primary_common_name, language: language.upcase, primary: true)
        result = plant.save
        errors = errors_from_active_record plant.errors
        {
          plant: result ? plant : nil,
          errors: errors
        }
      end
    end
  end
end
