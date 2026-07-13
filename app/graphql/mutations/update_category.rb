# frozen_string_literal: true

module Mutations
  # Modifies editble fields for a Category
  class UpdateCategory < BaseMutation
    argument :category_id, ID, required: true, loads: Types::CategoryType

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

    field :category, Types::CategoryType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(category:, **attributes)
      authorize category, :update?
      authorize_visibility_transition(category, attributes[:visibility])
      true
    end

    def resolve(category:, **attributes)
      if attributes.key?(:visibility)
        Rails.logger.info(
          "legacy_contract.visibility_arg mutation=UpdateCategory category_id=#{category.id}"
        )
      end

      # When transitioning to deleted, stamp deleted_by_principal_id.
      vis = attributes[:visibility]
      if vis && vis.to_s.casecmp('deleted').zero? && category.visibility.to_s != 'deleted'
        attributes[:deleted_by_principal_id] = context[:current_user]&.principal&.id
      end

      language = attributes[:language] || I18n.locale

      Mobility.with_locale(language) do
        category.update(attributes.except(:language))
        {
          category: category,
          errors: errors_from_active_record(category.errors)
        }
      end
    end
  end
end
