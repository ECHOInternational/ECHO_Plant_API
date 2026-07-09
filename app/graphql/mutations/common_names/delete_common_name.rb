# frozen_string_literal: true

module Mutations
  module CommonNames
    # Deletes a common name
    class DeleteCommonName < BaseMutation
      argument :common_name_id, ID, required: true, loads: Types::CommonNameType

      field :common_name_id, ID, null: true
      field :errors, [Types::MutationError], null: false

      def authorized?(common_name:, **_attributes)
        authorize common_name.plant, :update?
      end

      def resolve(common_name:)
        id = PlantApiSchema.id_from_object(common_name, CommonName, {})
        result = common_name.destroy
        {
          common_name_id: result ? id : nil,
          errors: errors_from_active_record(common_name.errors)
        }
      end
    end
  end
end
