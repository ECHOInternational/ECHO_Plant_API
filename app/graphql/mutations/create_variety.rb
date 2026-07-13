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
    argument :organization_id, ID,
             required: false,
             description: 'Relay global ID of the organization on whose behalf this variety is created. Defaults to the personal organization.'

    include Mutations::Concerns::VarietyEditableArguments
    include Mutations::Concerns::RangeLiteralValidation

    field :variety, Types::VarietyType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(plant:, **_attributes)
      # Creating a child requires read access to the referenced parent
      # (design.md section 6): you may build on another organization's
      # public/readable plant, but not reference one you cannot see.
      authorize plant, :show?
      authorize Variety, :create?
    end

    def resolve(**attributes) # rubocop:disable Metrics/AbcSize
      range_errors = validate_range_literals(attributes)
      return { variety: nil, errors: range_errors } if range_errors.any?

      language = attributes[:language] || I18n.locale

      org_id_arg = attributes.delete(:organization_id)
      if org_id_arg
        stamp, err = acting_organization_stamp(org_id_arg)
        return { variety: nil, errors: [err] } if err

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
