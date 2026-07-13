# frozen_string_literal: true

module Types
  # Defines fields for a specimen - categories contains a group of plant objects
  class SpecimenType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    include Types::Concerns::CapabilityFields

    description 'A specimen is an instance of a plant or a single group planting.'

    field :uuid, ID,
          description: 'The internal database ID for a specimen',
          null: false, method: :id
    field :name, String,
          description: 'The user assigned name of a specimen',
          null: true
    field :created_by, String,
          description: "The user ID of a specimen's creator",
          null: true,
          deprecation_reason: 'Use createdByPrincipal; email-based ownership is being retired.'
    field :owned_by, String,
          description: "The user ID of a specimen's owner",
          null: true,
          deprecation_reason: 'Use ownerOrganization; email-based ownership is being retired.'
    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a specimen',
          null: true
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the specimen. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
          null: false,
          deprecation_reason: 'Use publicationState/accessLevel/deletedAt.'

    # New ownership/provenance fields (design.md section 4 and 8).
    field :owner_organization, Types::OrganizationType, null: true,
                                                        description: 'The organization that owns this specimen.'
    field :source_organization, Types::OrganizationType, null: true,
                                                         description: 'The organization that originally sourced this specimen.'
    field :created_by_principal, Types::PrincipalType, null: true,
                                                       description: 'The principal that created this specimen.'
    field :publication_state, Types::PublicationStateEnum, null: true,
                                                           description: 'Whether this specimen is a draft or published.'
    field :access_level, Types::AccessLevelEnum, null: true,
                                                 description: 'Whether this specimen is visible to the owning organization only or publicly.'
    field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true,
                                                        description: 'When this specimen was soft-deleted, or null if not deleted.'
    field :plant, Types::PlantType,
          description: 'The kind of plant this specimen is',
          null: false
    field :variety, Types::VarietyType,
          description: 'The variety of plant this specimen is',
          null: true
    field :terminated, Boolean,
          description: 'Indicates whether or not this plant is still growing',
          null: false
    field :successful, Boolean,
          description: 'Indicates if the user believes this was successful',
          null: true
    field :recommended, Boolean,
          description: 'Indicates if the user would recommend this to others',
          null: true
    field :saved_seed, Boolean,
          description: 'Indicates if the user saved seeds collected from this specimen',
          null: true
    field :will_share_seed, Boolean,
          description: 'Indicates if the user plans to share seeds collected from this specimen',
          null: true
    field :will_plant_again, Boolean,
          description: 'Indicates if the user plans to plant this again',
          null: true
    field :notes, String,
          description: 'User supplied notes about the experience with this specimen',
          null: true
    field :life_cycle_events, Types::LifeCycleEventType::LifeCycleEventConnectionWithTotalCountType,
          description: 'A list of life cycle events for this specimen, ordered by date ascending',
          null: true,
          connection: true
    field :evaluated_at, GraphQL::Types::ISO8601DateTime,
          description: 'The date and time that the specimen was last evaluated',
          null: true
    field :created_at, GraphQL::Types::ISO8601DateTime,
          description: 'The date and time that the record was created',
          null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime,
          description: 'The date and time that the record was last updated',
          null: false

    def life_cycle_events
      @object.life_cycle_events.order(datetime: :asc)
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

    # CapabilityFields overrides: Specimen uses destroy? for delete; no restore.
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
