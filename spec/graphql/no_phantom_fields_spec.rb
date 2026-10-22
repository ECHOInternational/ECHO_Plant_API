# frozen_string_literal: true

require 'rails_helper'

# A "phantom field" is a schema field that the type advertises but nothing can
# resolve: it has no resolver method on the GraphQL type and the backing model
# does not respond to the method the field delegates to. Such a field passes
# schema dump and compiles, then raises NoMethodError the first time a client
# selects it. (Image.translations was one: it delegated to a model method that
# was never written.)
#
# The check walks every object type whose GraphQL name matches a model class,
# so it covers scalar, list and composite (object-typed) fields alike.
# Types with no matching model constant (payloads, hash-backed translation
# types, connection wrappers) are out of scope here; their fields are
# resolved from hashes and are exercised by the behaviour specs.
RSpec.describe 'GraphQL schema has no phantom fields' do
  # Entries are 'TypeName.fieldName' strings. Each needs a comment saying why
  # the field is allowed although the static check cannot resolve it.
  #
  # Variety.earlyGrowthPhase and Variety.lifeCycle are KNOWN pre-existing
  # phantoms (varieties has no such columns; they exist on plants only). No
  # client selects them. They are listed rather than fixed because removing or
  # backing them is a schema decision outside this spec's scope; follow-up.
  let(:allowed_phantoms) { %w[Variety.earlyGrowthPhase Variety.lifeCycle] }

  def backing_model(type)
    constant = type.graphql_name.safe_constantize
    constant if constant.is_a?(Class)
  end

  def model_responds_to?(model, method_sym)
    name = method_sym.to_s
    model.method_defined?(method_sym) ||
      (model.respond_to?(:attribute_types) && model.attribute_types.key?(name)) ||
      (model.respond_to?(:reflect_on_association) && model.reflect_on_association(method_sym).present?)
  end

  def object_types
    PlantApiSchema.types.values.select do |type|
      type.is_a?(Class) && type < GraphQL::Schema::Object &&
        !type.graphql_name.start_with?('__') && !type.graphql_name.end_with?('Payload')
    end
  end

  # Fields the static check does not judge: resolver classes and fields read
  # from a hash key.
  def self_resolving?(field)
    field.resolver.present? || field.hash_key.is_a?(Symbol) || field.hash_key.is_a?(String)
  end

  def phantom?(type, model, field)
    return false if self_resolving?(field)
    return false if type.method_defined?(field.resolver_method)

    !model_responds_to?(model, field.method_sym)
  end

  def phantom_fields
    object_types.flat_map do |type|
      model = backing_model(type)
      next [] unless model

      type.fields.values.select { |field| phantom?(type, model, field) }
                        .map { |field| "#{type.graphql_name}.#{field.graphql_name}" }
    end
  end

  it 'finds model-backed object types to check' do
    names = object_types.filter_map { |type| type.graphql_name if backing_model(type) }
    expect(names).to include('Plant', 'Image', 'Category', 'Specimen')
  end

  it 'has no field that neither the type nor its model can resolve' do
    expect(phantom_fields - allowed_phantoms).to eq([])
  end

  it 'keeps the allow-list free of stale entries' do
    expect(allowed_phantoms - phantom_fields).to eq([])
  end
end
