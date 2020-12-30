# frozen_string_literal: true

# Defines the GraphQL Plant API Schema
class PlantApiSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # Opt in to the new runtime (default in future graphql-ruby versions)
  use GraphQL::Execution::Interpreter
  use GraphQL::Analysis::AST
  use GraphQL::Execution::Errors

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

  # Add built-in connections for pagination
  use GraphQL::Pagination::Connections

  # Relay Object Identification:

  # Return a string UUID for `object`
  def self.id_from_object(object, type_definition, _query_ctx)
    # Here's a simple implementation which:
    # - joins the type name & object.id
    # - encodes it with base64:
    GraphQL::Schema::UniqueWithinType.encode(type_definition.name, object.id)
  end

  # Given a string UUID, find the object
  def self.object_from_id(id, _query_ctx)
    begin
      type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)
      klass = type_name.constantize
    rescue NameError
      raise GraphQL::ExecutionError.new(
        "Not Found: #{id} not found.",
        extensions: { 'code' => 404 }
      )
    rescue ArgumentError
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
    when ImageAttribute
      Types::ImageAttributeType
    when Antinutrient
      Types::AntinutrientType
    when Tolerance
      Types::ToleranceType
    when Plant
      Types::PlantType
    when Variety
      Types::VarietyType
    when Specimen
      Types::SpecimenType
    when Location
      Types::LocationType
    else
      raise("Not Implemented: #{obj}")
    end
  end
end
