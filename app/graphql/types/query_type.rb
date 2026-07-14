# frozen_string_literal: true

module Types
  # Defines the available queries for the Plant API
  class QueryType < Types::BaseObject # rubocop:disable Metrics/ClassLength
    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    # Relay node lookups. We do NOT include HasNodeField/HasNodesField: their
    # default resolver calls object_from_id (a raw find) and would return any
    # record by global ID, bypassing OwnedResourcePolicy::Scope and leaking
    # private/cross-org records (and enumerating principal emails / org names).
    # These custom resolvers authorize every lookup through the same policy
    # scope the single-object queries use.
    field :node, GraphQL::Types::Relay::Node, null: true,
                                              description: 'Fetches an object given its ID.' do
      argument :id, ID, required: true, description: 'ID of the object.'
    end
    def node(id:)
      authorized_node(id)
    end

    field :nodes, [GraphQL::Types::Relay::Node, { null: true }], null: false,
                                                                 description: 'Fetches a list of objects given a list of IDs.' do
      argument :ids, [ID], required: true, description: 'IDs of the objects.'
    end
    def nodes(ids:)
      ids.map { |id| authorized_node(id) }
    end

    # Identity query: the currently authenticated user, or null for anonymous.
    field :me, Types::MeType, null: true,
                              description: 'The currently authenticated user. Null when the request is anonymous.'

    # Collection Queries
    field :categories, resolver: Resolvers::CategoriesResolver, connection: true
    field :image_attributes, resolver: Resolvers::ImageAttributesResolver, connection: true
    field :antinutrients, resolver: Resolvers::AntinutrientsResolver, connection: true
    field :tolerances, resolver: Resolvers::TolerancesResolver, connection: true
    field :growth_habits, resolver: Resolvers::GrowthHabitsResolver, connection: true
    field :plants, resolver: Resolvers::PlantsResolver, connection: true
    field :varieties, resolver: Resolvers::VarietiesResolver, connection: true
    field :specimens, resolver: Resolvers::SpecimensResolver, connection: true
    field :locations, resolver: Resolvers::LocationsResolver, connection: true

    # Object Queries
    field :life_cycle_event, Types::LifeCycleEventType, null: true do
      description 'Find a life cycle event by ID'
      argument :id,
               type: ID,
               required: true
    end
    def life_cycle_event(id:)
      item_id = decode_global_id(id)
      Pundit.policy_scope(context[:current_user], LifeCycleEvent).find(item_id)
    end
    field :plant, Types::PlantType, null: true do
      description 'Find a plant by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific languge. Overrides ACCEPT-LANGUAGE header.'
    end
    def plant(id:, language: nil)
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      Pundit.policy_scope(context[:current_user], Plant).find(item_id)
    end
    field :variety, Types::VarietyType, null: true do
      description 'Find a variety by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific languge. Overrides ACCEPT-LANGUAGE header.'
    end
    def variety(id:, language: nil)
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      Pundit.policy_scope(context[:current_user], Variety).find(item_id)
    end

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
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      Pundit.policy_scope(context[:current_user], Category).find(item_id)
    end

    field :specimen, Types::SpecimenType, null: true do
      description 'Find a specimen by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific languge. Overrides ACCEPT-LANGUAGE header.'
    end
    def specimen(id:, language: nil)
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      Pundit.policy_scope(context[:current_user], Specimen).find(item_id)
    end

    field :location, Types::LocationType, null: true do
      description 'Find a location by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific languge. Overrides ACCEPT-LANGUAGE header.'
    end
    def location(id:, language: nil)
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      Pundit.policy_scope(context[:current_user], Location).find(item_id)
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
      item_id = decode_global_id(id)
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
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      Antinutrient.find(item_id)
    end

    field :tolerance, Types::ToleranceType, null: true do
      description 'Find a tolerance by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
    end
    def tolerance(id:, language: nil)
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      Tolerance.find(item_id)
    end

    field :growth_habit, Types::GrowthHabitType, null: true do
      description 'Find a growth habit by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
    end
    def growth_habit(id:, language: nil)
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      GrowthHabit.find(item_id)
    end

    field :organization, Types::OrganizationType, null: true do
      description 'Look up an organization by ID. Requires authentication.'
      argument :id,
               type: ID,
               required: true
    end
    def organization(id:)
      # Authenticated-only: a nil current_user raises NotAuthorizedError, which
      # the schema rescue maps to a 401 (403 for an authenticated-but-forbidden
      # user, which cannot happen here). Any authenticated user may resolve an
      # org by id -- names/kinds are not sensitive; membership lives on `me`.
      raise Pundit::NotAuthorizedError, 'authentication required' unless context[:current_user]

      item_id = decode_global_id(id)
      Organization.find(item_id)
    end

    field :sync_conflicts, [Types::SyncConflictType], null: false do
      description "List sync conflicts. Scoped to the current user's organizations."
      argument :status, Types::SyncConflictStatusEnum, required: false
    end
    def sync_conflicts(status: nil)
      user = context[:current_user]
      base = SyncConflict.all
      base = base.where(status: status.downcase) if status

      if user&.admin?
        base.includes(:data_source, :syncable)
      elsif user
        org_ids = user.readable_organization_ids
        conflict_ids = []
        base.includes(:syncable).find_each do |conflict|
          syncable = conflict.syncable
          next unless syncable
          next unless org_ids.include?(syncable.owner_organization_id)
          next unless user.organization_capability?(syncable.owner_organization_id, :resolve_conflicts)

          conflict_ids << conflict.id
        end
        SyncConflict.where(id: conflict_ids).includes(:data_source, :syncable)
      else
        SyncConflict.none
      end
    end

    def me
      context[:current_user]
    end

    # Policy-governed models reachable by global ID. Resolved through their
    # Pundit scope so node()/nodes() cannot see records the single-object
    # queries would hide.
    NODE_POLICY_SCOPED = {
      'Plant' => Plant, 'Variety' => Variety, 'Specimen' => Specimen,
      'Location' => Location, 'Category' => Category, 'Image' => Image,
      'LifeCycleEvent' => LifeCycleEvent
    }.freeze

    private

    # Authorized Relay node lookup shared by node()/nodes(). Identity/provenance
    # types are never node-addressable (would enumerate emails/org names);
    # policy-governed types resolve through their scope (missing OR invisible ->
    # coded 404 via the schema rescue, indistinguishable, no existence oracle);
    # lookups resolve directly.
    def authorized_node(id)
      type_name, item_id = decode_node_id(id)
      raise not_found_error(id) if PlantApiSchema::NODE_FORBIDDEN_TYPES.include?(type_name)

      klass = NODE_POLICY_SCOPED[type_name]
      return PlantApiSchema.object_from_id(id, context) if klass.nil?

      Pundit.policy_scope(context[:current_user], klass).find(item_id)
    rescue ActiveRecord::RecordNotFound
      # Missing OR invisible -> same coded 404, no existence oracle.
      raise not_found_error(id)
    end

    # Decodes a node global id, converting the decoder's version-dependent
    # error (ArgumentError or a bare GraphQL::ExecutionError with no code) into
    # our coded 404 contract for a malformed id.
    def decode_node_id(id)
      GraphQL::Schema::UniqueWithinType.decode(id)
    rescue ArgumentError, GraphQL::ExecutionError
      raise GraphQL::ExecutionError.new(
        "Not Found: #{id} not found. The provided ID is in an invalid format.",
        extensions: { 'code' => 404 }
      )
    end

    def not_found_error(id)
      GraphQL::ExecutionError.new("Not Found: #{id} not found.", extensions: { 'code' => 404 })
    end

    # Decodes a Relay global ID, matching the error shape of PlantApiSchema.object_from_id
    # so that malformed IDs on single-object queries yield the same coded 404 as the node()
    # field (unified at pre-promo 3; was a raw 500 on Rails 6 production).
    def decode_global_id(id)
      _type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)
      item_id
    rescue ArgumentError, GraphQL::ExecutionError
      # graphql-ruby's base64 decoder raises ArgumentError on a malformed id in some
      # versions and wraps it as a bare GraphQL::ExecutionError (no extensions.code)
      # in others. Rescue both to guarantee a coded 404 regardless of which exception
      # the decoder surfaces (mirrors the dual-class rescue in object_from_id).
      raise GraphQL::ExecutionError.new(
        "Not Found: #{id} not found. The provided ID is in an invalid format.",
        extensions: { 'code' => 404 }
      )
    end
  end
end
