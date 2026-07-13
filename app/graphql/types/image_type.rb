# frozen_string_literal: true

module Types
  # Defines fields for an Image
  class ImageType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    include Types::Concerns::CapabilityFields

    description 'Images can be associated with most data types in the Plant API'

    field :uuid, ID,
          description: 'The internal database ID for an image',
          null: false,
          method: :id
    field :name, String,
          description: 'The translated name of an image',
          null: true
    field :description, String,
          description: 'A translated description of an image',
          null: true
    field :attribution, String,
          description: 'Copyright and attribution data',
          null: true
    field :base_url, String,
          description: 'The URL for the image',
          null: false
    field :image_attributes, [Types::ImageAttributeType],
          description: 'A list of attributes for this image',
          null: false
    field :created_by, String,
          description: "The user ID of an image's creator",
          null: true,
          deprecation_reason: 'Use ownerOrganization on the imageable; email-based ownership is being retired.'
    field :owned_by, String,
          description: "The user ID of an image's owner",
          null: true,
          deprecation_reason: 'Use ownerOrganization on the imageable; email-based ownership is being retired.'
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the image. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
          null: false,
          deprecation_reason: 'Use publicationState/accessLevel/deletedAt.'
    field :translations, [Types::CategoryType::CategoryTranslationType],
          description: 'Translations of translatable category fields',
          null: false,
          method: :translations_array

    def visibility
      @object.visibility.to_sym
    end

    # CapabilityFields overrides: Image uses destroy? for delete; no restore.
    def delete_policy_method
      :destroy?
    end

    def restore_policy_method
      nil
    end
  end
end
