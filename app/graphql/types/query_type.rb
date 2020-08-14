# frozen_string_literal: true

module Types
  # Defines the available queries for the Plant API
  class QueryType < Types::BaseObject
    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    # Used by Relay to lookup objects by UUID:
    add_field(GraphQL::Types::Relay::NodeField)
    # Fetches a list of objects given a list of IDs
    add_field(GraphQL::Types::Relay::NodesField)

    # Collection Queries
    field :categories, resolver: Resolvers::CategoriesResolver, connection: true
    field :image_attributes, resolver: Resolvers::ImageAttributesResolver, connection: true
    field :antinutrients, resolver: Resolvers::AntinutrientsResolver, connection: true

    # Object Queries
    field :category, Types::CategoryType, null: true do
      description 'Find a category by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific languge. Overrides ACCEPT-LANGUAGE header.'
    end
    def category(id:, language: nil)
      _type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)
      Mobility.locale = language || I18n.locale
      Pundit.policy_scope(context[:current_user], Category).find(item_id)
    end

    field :image_attribute, Types::ImageAttributeType, null: true do
      description 'Find an image attribute by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
    end
    def image_attribute(id:, language: nil)
      _type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)
      Mobility.locale = language || I18n.locale
      ImageAttribute.find(item_id)
    end

    field :antinutrient, Types::AntinutrientType, null: true do
      description 'Find an antinutrient by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
    end
    def antinutrient(id:, language: nil)
      _type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)
      Mobility.locale = language || I18n.locale
      Antinutrient.find(item_id)
    end
  end
end
