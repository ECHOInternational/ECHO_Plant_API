# frozen_string_literal: true

module Mutations
  module CommonNames
    # Makes a common name the primary name for its plant and language,
    # demoting any current primary.
    class SetPrimaryCommonName < BaseMutation
      argument :common_name_id, ID, required: true, loads: Types::CommonNameType

      field :common_name, Types::CommonNameType, null: true
      field :errors, [Types::MutationError], null: false

      def authorized?(common_name:, **_attributes)
        authorize common_name.plant, :update?
      end

      def resolve(common_name:)
        CommonName.transaction do
          common_name.plant.common_names
                     .where(language: common_name.language, primary: true)
                     .where.not(id: common_name.id)
                     .update_all(primary: false)
          common_name.update(primary: true)
        end
        {
          common_name: common_name,
          errors: errors_from_active_record(common_name.errors)
        }
      end
    end
  end
end
