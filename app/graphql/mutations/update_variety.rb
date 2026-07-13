# frozen_string_literal: true

module Mutations
  # Modifies editable fields for a Variety
  class UpdateVariety < BaseMutation
    argument :variety_id, ID, required: true, loads: Types::VarietyType

    argument :plant_id, ID, required: false, loads: Types::PlantType
    argument :name, String, required: false
    argument :description, String, required: false
    argument :language, String, required: false
    argument :visibility, Types::VisibilityEnum, required: false
    argument :publication_state, Types::PublicationStateEnum,
             required: false,
             description: 'New publication state (DRAFT or PUBLISHED).'
    argument :access_level, Types::AccessLevelEnum,
             required: false,
             description: 'New access level (ORGANIZATION or PUBLIC).'

    include Mutations::Concerns::VarietyEditableArguments
    include Mutations::Concerns::RangeLiteralValidation

    field :variety, Types::VarietyType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(variety:, **attributes)
      authorize variety, :update?
      authorize_visibility_transition(variety, attributes[:visibility])
      true
    end

    def resolve(variety:, **attributes)
      if attributes.key?(:visibility)
        Rails.logger.info(
          "legacy_contract.visibility_arg mutation=UpdateVariety variety_id=#{variety.id}"
        )
      end

      range_errors = validate_range_literals(attributes)
      return { variety: variety, errors: range_errors } if range_errors.any?

      language = attributes[:language] || I18n.locale

      # When transitioning to deleted, stamp deleted_by_principal_id.
      vis = attributes[:visibility]
      if vis && vis.to_s.casecmp('deleted').zero? && variety.visibility.to_s != 'deleted'
        attributes[:deleted_by_principal_id] = context[:current_user]&.principal&.id
      end

      Mobility.with_locale(language) do
        variety.update(attributes.except(:language))
        {
          variety: variety,
          errors: errors_from_active_record(variety.errors)
        }
      end
    end
  end
end
