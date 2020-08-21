class LifecycleeventGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('templates', __dir__)

  argument :fields, type: :array, default: [], banner: 'fields method'

  def setup # rubocop:disable Metrics/AbcSize
    @class_name = "#{file_name.camelcase}Event"
    @type_name = "#{@class_name}Type"
    @all_fields = {}
    fields.each do |field|
      name, type, required = field.split(':')
      @all_fields[name] = {}
      @all_fields[name][:type] = type
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

  # def generate_templates
  #   policy_path = 'app/policies/life_cycle_events'
  #   graphql_type_path = 'app/graphql/types'
  #   graphql_mutations_path = 'app/graphql/mutations'
  #   graphql_resolvers_path = 'app/graphql/resolvers'

  #   template "service.erb", generator_path

	# 	generator_dir_path = service_dir_path + ("/#{@module_name.underscore}" if @module_name.present?).to_s
	# 	generator_path = generator_dir_path + "/#{file_name}.rb"

  # end
end