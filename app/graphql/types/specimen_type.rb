# frozen_string_literal: true

module Types
  # Defines fields for a specimen - categories contains a group of plant objects
  class SpecimenType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A specimen is an instance of a plant or a single group planting.'

    field :uuid, ID,
          description: 'The internal database ID for a specimen',
          null: false,method: :id
    field :name, String,
          description: 'The user assigned name of a specimen',
          null: true
    field :created_by, String,
          description: "The user ID of a specimen's creator",
          null: true
    field :owned_by, String,
          description: "The user ID of a specimen's owner",
          null: true
    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a specimen',
          null: true
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the specimen. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
          null: false
    field :plant, Types::PlantType,
          description: 'The kind of plant this specimen is',
          null: false
    field :variety, Types::VarietyType,
          description: 'The variety of plant this specimen is',
          null: true
    field :terminated, Boolean,
          description: 'Indicates whether or not this plant is still growing',
          null: false

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end

    def visibility
      @object.visibility.to_sym
    end

    # def versions
    # @object.translation.versions.where(event: "update").reorder('created_at DESC')
    # end
  end
end
