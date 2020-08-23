# frozen_string_literal: true

# Generates Life Cycle Event Types
class LifecycleeventGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('templates', __dir__)

  argument :fields, type: :array, default: [], banner: 'fields method'

  def setup # rubocop:disable Metrics/AbcSize
    @friendly_name = file_name.titleize
    @name = file_name.camelcase
    @mutation_suffix = "#{@name}LifeCycleEvent"
    @class_name = "#{@name}Event"
    @type_name = "#{@class_name}Type"
    @sample_values = FactoryBot.build(:life_cycle_event)
    @all_fields = {}
    fields.each do |field|
      name, type, required = field.split(':')
      @all_fields[name] = {}
      @all_fields[name][:type] = type.gsub('/', '::')
      @all_fields[name][:required] = required == 'required'
      @all_fields[name][:sample] = sample_value_for name
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
    factory_path = "spec/factories/#{@class_name.underscore}.rb"
    template 'factory.rb.erb', factory_path
  end

  def generate_model_spec
    model_spec_path = "spec/models/#{@class_name.underscore}_spec.rb"
    template 'model_spec.rb.erb', model_spec_path
  end

  def generate_query_spec
    query_spec_path = "spec/queries/#{@class_name.underscore}_query_spec.rb"
    template 'query_spec.rb.erb', query_spec_path
  end

  def generate_create_mutation_spec
    create_mutation_spec_path = "spec/mutations/add_#{@name.underscore.downcase}_life_cycle_event_spec.rb"
    template 'create_mutation_spec.rb.erb', create_mutation_spec_path
  end

  def generate_update_mutation_spec
    update_mutation_spec_path = "spec/mutations/update_#{@name.underscore.downcase}_life_cycle_event_spec.rb"
    template 'update_mutation_spec.rb.erb', update_mutation_spec_path
  end

  def append_comment_to_life_cycle_events_interface
    open('app/graphql/types/life_cycle_event_type.rb', 'a') { |f|
      f.puts <<-COMMENT
      when #{@class_name}
        Types::#{@type_name}
      COMMENT
    }
  end

  def append_comment_to_mutations_type
    open('app/graphql/types/mutation_type.rb', 'a') { |f|
      f.puts <<-TEXT
      field :add_#{@class_name.underscore}_to_specimen,
            mutation: Mutations::LifeCycleEvents::Add#{@name}LifeCycleEvent,
            description: 'Adds a #{@friendly_name} life cycle event to a specimen'
      field :update_#{@class_name.underscore},
            mutation: Mutations::LifeCycleEvents::Update#{@name}LifeCycleEvent,
            description: 'Updates a #{@friendly_name} life cycle event'
      TEXT
    }
  end

  def post_run_notices
    puts "Don't forget to add commented lines at bottom of mutatio_type and life_cycle_event_type definitions."
    puts 'Failing tests are usually cause by forgetting the above or not implementing special types in tests'
  end

  private

  def sample_value_for(name)
    klass = LifeCycleEvent.type_for_attribute(name)
    value = @sample_values.send(name)

    return value if value.is_a? Numeric

    case klass
    when Numeric
      value
    when ActiveModel::Type::String
      "'#{value}'"
    when ActiveRecord::Enum::EnumType
      "'#{value.upcase}'"
    else
      "'TODO: Replace unsupported Value #{klass}'"
    end
  end
end
