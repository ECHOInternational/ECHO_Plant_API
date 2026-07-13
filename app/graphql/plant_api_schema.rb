# frozen_string_literal: true

# Defines the GraphQL Plant API Schema
class PlantApiSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  orphan_types [Types::AcquireEventType]

  rescue_from(ActiveRecord::RecordNotFound) do |err, _obj, _args, _ctx, _field|
    # Raise a graphql-friendly error with a custom message

    object_not_found_id = GraphQL::Schema::UniqueWithinType.encode(err.model, err.id)
    raise GraphQL::ExecutionError.new(
      "Not Found: #{err.model} #{object_not_found_id} not found.",
      extensions: { 'code' => 404 }
    )
  end

  # Return a GraphQL error if the user is not authorized to take this action
  # a 401 will be returned if the user is not authenticated to the system
  # a 403 will be returned if the user is not authorized to take this action
  rescue_from(Pundit::NotAuthorizedError) do |err, _obj, _args, ctx, _fields|
    class_name = err.record.is_a?(Class) ? err.record.name : err.record.class.name
    method_called = err.query.to_s.delete_suffix('?')

    raise GraphQL::ExecutionError.new(
      "Unauthorized: User cannot #{method_called} this #{class_name}.",
      extensions: { 'code' => ctx[:current_user] ? 403 : 401 }
    )
  end

  # Relay Object Identification:

  # Return a string UUID for `object`
  def self.id_from_object(object, type_definition, _query_ctx)
    # Here's a simple implementation which:
    # - joins the type name & object.id
    # - encodes it with base64:
    #
    # graphql-ruby 1.13 passes a class-based GraphQL type here, whose `.name`
    # is now the Ruby class name (e.g. "Types::SpecimenType") rather than the
    # GraphQL type name. Prefer `graphql_name` ("Specimen") so the public
    # global-ID format (TypeName + UUID) stays byte-identical. Fall back to
    # `.name` for callers that pass a model class directly (its `.name`
    # already equals the GraphQL type name).
    type_name = type_definition.respond_to?(:graphql_name) ? type_definition.graphql_name : type_definition.name
    GraphQL::Schema::UniqueWithinType.encode(type_name, object.id)
  end

  # Identity/provenance models must never be addressable by a top-level Relay
  # node(id:) probe: they are exposed only as nested fields of an already-
  # authorized parent (ownerOrganization, createdByPrincipal) or through their
  # own scoped query (syncConflicts). Enforced in QueryType's node/nodes
  # resolvers, which also apply Pundit show? to policy-governed records.
  NODE_FORBIDDEN_TYPES = %w[Principal Organization DataSource SyncConflict].freeze

  # Given a string UUID, find the object. NOTE: this is a raw lookup with no
  # authorization -- callers are responsible for authorizing the result.
  # Mutation `loads:` arguments and manual loads authorize via the mutation's
  # own `authorized?`/`authorize` calls; the Relay node/nodes fields authorize
  # in QueryType (they must not leak records the caller cannot see).
  def self.object_from_id(id, _query_ctx)
    begin
      type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)
      klass = type_name.constantize
    rescue NameError
      raise GraphQL::ExecutionError.new(
        "Not Found: #{id} not found.",
        extensions: { 'code' => 404 }
      )
    rescue ArgumentError, GraphQL::ExecutionError
      # graphql-ruby 1.13's base64 decoder catches the ArgumentError raised on a
      # malformed id and re-raises it as a plain GraphQL::ExecutionError
      # ("Invalid input: ...") that carries no extensions.code. Catch both so a
      # malformed global id keeps producing our coded 404 (contract), regardless
      # of which exception class the decoder surfaces.
      raise GraphQL::ExecutionError.new(
        "Not Found: #{id} not found. The provided ID is in an invalid format.",
        extensions: { 'code' => 404 }
      )
    end
    klass.find item_id
  end

  # Object Resolution
  def self.resolve_type(_type, obj, _ctx) # rubocop:disable all
    case obj
    when Category
      Types::CategoryType
    when Image
      Types::ImageType
    when Organization
      Types::OrganizationType
    when Principal
      Types::PrincipalType
    when ImageAttribute
      Types::ImageAttributeType
    when Antinutrient
      Types::AntinutrientType
    when GrowthHabit
      Types::GrowthHabitType
    when Tolerance
      Types::ToleranceType
    when CommonName
      Types::CommonNameType
    when Plant
      Types::PlantType
    when Variety
      Types::VarietyType
    when Specimen
      Types::SpecimenType
    when Location
      Types::LocationType
    when LifeCycleEvent
      Types::LifeCycleEventType.resolve_type(obj, _ctx)
    else
      raise("Not Implemented: #{obj}")
    end
  end
end
