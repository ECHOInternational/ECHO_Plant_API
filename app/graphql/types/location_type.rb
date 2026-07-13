# frozen_string_literal: true

module Types
  # Defines fields for a location - categories contains a group of plant objects
  class LocationType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    include Types::Concerns::CapabilityFields

    description 'A location is an instance of a plant or a single group planting.'

    field :uuid, ID,
          description: 'The internal database ID for a location',
          null: false,
          method: :id
    field :name, String,
          description: 'The user assigned name of a location',
          null: false
    field :created_by, String,
          description: "The user ID of a location's creator",
          null: true,
          deprecation_reason: 'Use createdByPrincipal; email-based ownership is being retired.'
    field :owned_by, String,
          description: "The user ID of a location's owner",
          null: true,
          deprecation_reason: 'Use ownerOrganization; email-based ownership is being retired.'
    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a location',
          null: true
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the location. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
          null: false,
          deprecation_reason: 'Use publicationState/accessLevel/deletedAt.'

    # New ownership/provenance fields (design.md section 4 and 8).
    field :owner_organization, Types::OrganizationType,
          null: true,
          description: 'The organization that owns this location.'
    field :source_organization, Types::OrganizationType,
          null: true,
          description: 'The organization that originally sourced this location.'
    field :created_by_principal, Types::PrincipalType,
          null: true,
          description: 'The principal that created this location.'
    field :publication_state, Types::PublicationStateEnum,
          null: true,
          description: 'Whether this location is a draft or published.'
    field :access_level, Types::AccessLevelEnum,
          null: true,
          description: 'Whether this location is visible to the owning organization only or publicly.'
    field :deleted_at, GraphQL::Types::ISO8601DateTime,
          null: true,
          description: 'When this location was soft-deleted, or null if not deleted.'
    field :soil_quality, Types::ConditionEnum,
          description: 'The general soil quality at the location',
          null: true
    field :latitude, Float,
          description: 'The latitude of the location',
          null: true
    field :longitude, Float,
          description: 'The longitude of the location',
          null: true
    field :area, Float,
          description: 'The total size of the location in hectares',
          null: true
    field :slope, Int,
          description: 'The slope of the land in degrees of the location',
          null: true
    field :altitude, Int,
          description: 'The altitude in meters of the location',
          null: true
    field :average_rainfall, Int,
          description: 'The average rainfall in mm of the location',
          null: true
    field :average_temperature, Int,
          description: 'The average temperature in degrees celsius of the location',
          null: true
    field :irrigated, Boolean,
          description: 'Indicates whether the location is irrigated',
          null: false
    field :notes, String,
          description: 'Description and notes about the location',
          null: true
    field :created_at, GraphQL::Types::ISO8601DateTime,
          description: 'The date and time that the record was created',
          null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime,
          description: 'The date and time that the record was last updated',
          null: false

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

    # CapabilityFields overrides: Location supports soft-delete and restore.
    def delete_policy_method
      :soft_delete?
    end

    def restore_policy_method
      :restore?
    end

    # def versions
    # @object.translation.versions.where(event: "update").reorder('created_at DESC')
    # end
  end
end
