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
    argument :family_id, GraphQL::Types::ID,
             required: false,
             loads: Types::FamilyType,
             description: 'The botanical family this plant belongs to'
    argument :language, String,
             required: false,
             description: 'Language of the translatable fields supplied'
    argument :visibility, Types::VisibilityEnum,
             required: false,
             description: 'The visibility of the plant'
    argument :organization_id, ID,
             required: false,
             description: 'Relay global ID of the organization on whose behalf this plant is created. Defaults to the personal organization.'

    include Mutations::Concerns::PlantEditableArguments
    include Mutations::Concerns::RangeLiteralValidation

    field :plant, Types::PlantType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(**_attributes)
      authorize Plant, :create?
    end

    def resolve(**attributes) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      range_errors = validate_range_literals(attributes)
      return { plant: nil, errors: range_errors } if range_errors.any?

      language = attributes[:language] || I18n.locale
      primary_common_name = attributes[:primary_common_name]

      org_id_arg = attributes.delete(:organization_id)
      stamp, err = if org_id_arg
                     acting_organization_stamp(org_id_arg)
                   else
                     ownership_stamp
                   end
      return { plant: nil, errors: [err] } if err

      org_stamp = stamp

      attributes
        .except!(:language)
        .except!(:primary_common_name)
        .merge!(created_by: context[:current_user].email)
        .merge!(owned_by: context[:current_user].email)
        .merge!(org_stamp)

      Mobility.with_locale(language) do
        plant = Plant.new(attributes.except(:family))
        # The legacy free-text column stays authoritative for whatever a human
        # typed. We only fill it in when it is empty, so a plant classified
        # through the new relation still shows something useful in the clients
        # that read family_names, without ever clobbering a person's own words.
        if attributes.key?(:family)
          plant.family = attributes[:family]
          plant.family_names = attributes[:family]&.name if plant.family_names.blank?
        end
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
