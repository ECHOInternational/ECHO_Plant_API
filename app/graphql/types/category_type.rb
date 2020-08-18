# frozen_string_literal: true

module Types
  # Defines fields for a category - categories contains a group of plant objects
  class CategoryType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

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
          null: true
    field :owned_by, String,
          description: "The user ID of a category's owner",
          null: true
    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a category',
          null: true
    field :translations, [Types::CategoryType::CategoryTranslationType],
          description: 'Translations of translatable category fields',
          null: false,
          method: :translations_array
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the category. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
          null: false
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

    # def versions
    # @object.translation.versions.where(event: "update").reorder('created_at DESC')
    # end
  end
end
