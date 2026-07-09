# frozen_string_literal: true

module Mutations
  module CommonNames
    # Adds a common name to a plant
    class AddCommonName < BaseMutation
      argument :plant_id, ID, required: true, loads: Types::PlantType
      argument :name, String, required: true
      argument :language, String, required: true
      argument :location, String, required: false
      argument :primary, Boolean, required: false, default_value: false

      field :common_name, Types::CommonNameType, null: true
      field :errors, [Types::MutationError], null: false

      def authorized?(plant:, **_attributes)
        authorize plant, :update?
      end

      def resolve(plant:, name:, language:, location: nil, primary: false)
        language = language.upcase
        common_name = plant.common_names.build(name: name, language: language, location: location, primary: primary)
        CommonName.transaction do
          plant.common_names.where(language: language, primary: true).update_all(primary: false) if primary
          common_name.save
        end
        {
          common_name: common_name.persisted? ? common_name : nil,
          errors: errors_from_active_record(common_name.errors)
        }
      end
    end
  end
end
