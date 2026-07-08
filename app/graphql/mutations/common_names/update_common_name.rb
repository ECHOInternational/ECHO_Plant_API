# frozen_string_literal: true

module Mutations
  module CommonNames
    # Modifies a common name's editable fields
    class UpdateCommonName < BaseMutation
      argument :common_name_id, ID, required: true, loads: Types::CommonNameType
      argument :name, String, required: false
      argument :location, String, required: false

      field :common_name, Types::CommonNameType, null: true
      field :errors, [Types::MutationError], null: false

      def authorized?(common_name:, **_attributes)
        authorize common_name.plant, :update?
      end

      def resolve(common_name:, **attributes)
        common_name.update(attributes)
        {
          common_name: common_name,
          errors: errors_from_active_record(common_name.errors)
        }
      end
    end
  end
end
