# frozen_string_literal: true

module Mutations
  # Modifies editable fields for a Plant
  class UpdatePlant < BaseMutation
    argument :plant_id, ID, required: true, loads: Types::PlantType

    argument :primary_common_name, String, required: false
    argument :description, String, required: false
    argument :scientific_name, String, required: false
    argument :family_names, String, required: false
    argument :language, String, required: false
    argument :visibility, Types::VisibilityEnum, required: false
    argument :publication_state, Types::PublicationStateEnum,
             required: false,
             description: 'New publication state (DRAFT or PUBLISHED).'
    argument :access_level, Types::AccessLevelEnum,
             required: false,
             description: 'New access level (ORGANIZATION or PUBLIC).'

    include Mutations::Concerns::PlantEditableArguments
    include Mutations::Concerns::RangeLiteralValidation
    include Mutations::Concerns::FamilyAssignment

    field :plant, Types::PlantType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(plant:, **attributes)
      authorize plant, :update?
      authorize_visibility_transition(plant, attributes[:visibility])
      true
    end

    def resolve(plant:, **attributes) # rubocop:disable Metrics/AbcSize
      range_errors = validate_range_literals(attributes)
      return { plant: plant, errors: range_errors } if range_errors.any?

      language = attributes[:language] || I18n.locale
      primary_common_name = attributes[:primary_common_name]

      # When transitioning to deleted, stamp deleted_by_principal_id.
      vis = attributes[:visibility]
      if vis && vis.to_s.casecmp('deleted').zero? && plant.visibility.to_s != 'deleted'
        attributes[:deleted_by_principal_id] = context[:current_user]&.principal&.id
      end

      current_primary_common_names = plant.common_names.where(language: language.upcase).where(primary: true)
      current_primary_common_names.destroy_all if primary_common_name && current_primary_common_names.any?

      if primary_common_name
        plant.common_names.build(name: primary_common_name, language: language.upcase, primary: true)
      end

      Mobility.with_locale(language) do
        # Assign every other attribute (including any client-supplied
        # family_names) before applying the family mirror, so the mirror's
        # blank check sees what the client just sent rather than the stale
        # persisted value. This keeps the rule consistent with CreatePlant,
        # where Plant.new already applies attributes before the mirror runs.
        plant.assign_attributes(attributes.except(:language, :primary_common_name, :family))
        apply_family(plant, attributes)
        plant.save
        {
          plant: plant,
          errors: errors_from_active_record(plant.errors)
        }
      end
    end
  end
end
