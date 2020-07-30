module Types
  class CategoryType < Types::BaseObject
  	global_id_field :id

  	description "A category contains a group of plant objects."

  	field :uuid, ID, "The internal database ID for a category", null: false, method: :id
  	field :name, String, "The translated name of a category", null: true
  	field :description, String, "A translated description of a category", null: true
  	field :created_by, String, "The user ID of a category's creator", null: true
  	field :owned_by, String, "The user ID of a category's owner", null: true
    # field :images, Types::ImageType.connection_type, "A list of images related to a category", null: true
    # field :translations, [Types::CategoryType::CategoryTranslationType], "Translations of translatable category fields", null: false, method: :translations
    # field :versions, Types::CategoryType::CategoryVersionConnectionWithTotalCountType, null: false, connection: true

    # def versions
      # @object.translation.versions.where(event: "update").reorder('created_at DESC')
    # end
  end
end
