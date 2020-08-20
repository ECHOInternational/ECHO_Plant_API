# frozen_string_literal: true

# Defines the GraphQL Plant API Schema
class PlantApiSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # Opt in to the new runtime (default in future graphql-ruby versions)
  use GraphQL::Execution::Interpreter
  use GraphQL::Analysis::AST
  use GraphQL::Execution::Errors

  rescue_from(ActiveRecord::RecordNotFound) do |err, _obj, _args, _ctx, _field|
    # Raise a graphql-friendly error with a custom message

    # object_not_found_type = err.model.constantize
    # object_not_found_id = id_from_object(err.id, object_not_found_type, ctx)

    object_not_found_id = GraphQL::Schema::UniqueWithinType.encode(err.model, err.id)
    raise GraphQL::ExecutionError, "#{err.model}: #{object_not_found_id} not found."
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
    # For example, to decode the UUIDs generated abovcone:
    type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)
    #
    # Then, based on `type_name` and `id`
    # find an object in your application
    begin
      klass = type_name.constantize
    rescue NameError
      raise GraphQL::ExecutionError, "#{id} not found."
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
      Types::Variety
    when Specimen
      Types::Specimen
    else
      raise("Unexpected object: #{obj}")
    end
  end
end
