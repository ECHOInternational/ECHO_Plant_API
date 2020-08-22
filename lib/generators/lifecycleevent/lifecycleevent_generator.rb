# frozen_string_literal: true

# Generates Life Cycle Event Types
class LifecycleeventGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('templates', __dir__)

  argument :fields, type: :array, default: [], banner: 'fields method'

  def setup # rubocop:disable Metrics/AbcSize
    @friendly_name = file_name.titleize
    @mutation_suffix = "#{file_name.camelcase}LifeCycleEvent"
    @class_name = "#{file_name.camelcase}Event"
    @type_name = "#{@class_name}Type"
    @all_fields = {}
    fields.each do |field|
      name, type, required = field.split(':')
      @all_fields[name] = {}
      @all_fields[name][:type] = type.gsub('/', '::')
      @all_fields[name][:required] = required == 'required'
    end
    @required_fields = @all_fields.filter { |_field, attributes| attributes[:required] }
  end

  def generate_model
    @presence_validations = @required_fields.map { |k, _v| k.to_sym }
    model_path = "app/models/life_cycle_events/#{@class_name.underscore}.rb"
    template 'model.rb.erb', model_path
  end

  def generate_grapql_type
    type_path = "app/graphql/types/#{@type_name.underscore}.rb"
    template 'type.rb.erb', type_path
  end

  def generate_graphql_create_mutation
    @create_mutation_name = "Add#{@mutation_suffix}"
    mutation_path = "app/graphql/mutations/life_cycle_events/#{@create_mutation_name.underscore}.rb"
    template 'create_mutation.rb.erb', mutation_path
  end

  def generate_graphql_update_mutation
    @update_mutation_name = "Update#{@mutation_suffix}"
    mutation_path = "app/graphql/mutations/life_cycle_events/#{@update_mutation_name.underscore}.rb"
    template 'update_mutation.rb.erb', mutation_path
  end

  def generate_factory_bot_factory
    factory_path = "app/spec/factories/#{@class_name.underscore}.rb"
    template 'factory.rb.erb', factory_path
  end

  def generate_model_spec
    model_spec_path = "app/spec/models/#{@class_name.underscore}_spec.rb"
    template 'model_spec.rb.erb', model_spec_path
  end

  def post_run_notices
    puts "Be sure to add 'when #{@class_name}: #{file_name.camelcase}' to resolve_type in life_cycle_event interface."
  end
end
