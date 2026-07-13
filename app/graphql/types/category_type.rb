# frozen_string_literal: true

module Types
  # Defines fields for a category - categories contains a group of plant objects
  class CategoryType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    include Types::Concerns::CapabilityFields

    description 'A category contains a group of plant objects.'

    field :uuid, ID,
          description: 'The internal database ID for a category',
          null: false, method: :id
    field :name, String,
          description: 'The translated name of a category',
          null: true
    field :description, String,
          description: 'A translated description of a category',
          null: true
    field :created_by, String,
          description: "The user ID of a category's creator",
          null: true,
          deprecation_reason: 'Use createdByPrincipal; email-based ownership is being retired.'
    field :owned_by, String,
          description: "The user ID of a category's owner",
          null: true,
          deprecation_reason: 'Use ownerOrganization; email-based ownership is being retired.'
    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a category',
          null: true
    field :translations, [Types::CategoryType::CategoryTranslationType],
          description: 'Translations of translatable category fields',
          null: false,
          method: :translations_array
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the category. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
          null: false,
          deprecation_reason: 'Use publicationState/accessLevel/deletedAt.'

    # New ownership/provenance fields (design.md section 4 and 8).
    field :owner_organization, Types::OrganizationType,
          null: true,
          description: 'The organization that owns this category.'
    field :source_organization, Types::OrganizationType,
          null: true,
          description: 'The organization that originally sourced this category.'
    field :created_by_principal, Types::PrincipalType,
          null: true,
          description: 'The principal that created this category.'
    field :publication_state, Types::PublicationStateEnum,
          null: true,
          description: 'Whether this category is a draft or published.'
    field :access_level, Types::AccessLevelEnum,
          null: true,
          description: 'Whether this category is visible to the owning organization only or publicly.'
    field :deleted_at, GraphQL::Types::ISO8601DateTime,
          null: true,
          description: 'When this category was soft-deleted, or null if not deleted.'
    field :plants, Types::PlantType::PlantConnectionWithTotalCountType,
          description: 'The plants that belong to this category',
          null: true,
          connection: true
    # field :versions, Types::CategoryType::CategoryVersionConnectionWithTotalCountType, null: false, connection: true

    def plants
      Pundit.policy_scope(context[:current_user], @object.plants)
    end

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end

    def visibility
      @object.visibility.to_sym
    end

    # Resolvers for new ownership/provenance fields.
    def owner_organization
      return nil unless @object.owner_organization_id

      Organization.find_by(id: @object.owner_organization_id)
    end

    def source_organization
      return nil unless @object.source_organization_id

      Organization.find_by(id: @object.source_organization_id)
    end

    def created_by_principal
      return nil unless @object.created_by_principal_id

      Principal.find_by(id: @object.created_by_principal_id)
    end

    # CapabilityFields overrides: Category uses destroy? for delete; no restore.
    def delete_policy_method
      :destroy?
    end

    def restore_policy_method
      nil
    end

    # def versions
    # @object.translation.versions.where(event: "update").reorder('created_at DESC')
    # end
  end
end
