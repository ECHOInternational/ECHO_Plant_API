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

    field :variety, Types::VarietyType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(variety:, **_attributes)
      authorize variety, :update?
    end

    def resolve(variety:, **attributes)
      language = attributes[:language] || I18n.locale

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
