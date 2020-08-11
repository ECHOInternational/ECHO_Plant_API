module Types
  class ImageType < Types::BaseObject
    global_id_field :id

    description "Images can be associated with most data types in the Plant API"

    field :uuid, ID, "The internal database ID for an image", null: false, method: :id
    field :name, String, "The translated name of an image", null: true
    field :description, String, "A translated description of an image", null: true
    field :attribution, String, "Copyright and attribution data", null: true
    field :base_url, String, "The URL for the image", null: false
    field :image_attributes, [Types::ImageAttributeType], null: false
    field :created_by, String, "The user ID of an image's creator", null: true
    field :owned_by, String, "The user ID of an image's owner", null: true
    field :translations, [Types::CategoryType::CategoryTranslationType], "Translations of translatable category fields", null: false, method: :translations_array
  end
end
