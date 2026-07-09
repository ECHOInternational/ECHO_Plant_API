# frozen_string_literal: true

module Mutations
  module Lookups
    # Base mutation for updating simple translatable lookup records.
    # Subclasses declare their model with `lookup_model`.
    class UpdateLookupBaseMutation < BaseMutation
      class << self
        attr_reader :model_class, :record_key

        def lookup_model(klass, type:)
          @model_class = klass
          @record_key = klass.name.underscore.to_sym
          argument "#{klass.name.underscore}_id".to_sym, GraphQL::Types::ID, required: true, loads: type
          argument :name, String, required: false
          argument :language, String,
                   required: false,
                   description: 'Language of the translatable fields supplied'
          field record_key, type, null: true
          field :errors, [Types::MutationError], null: false
        end
      end

      def authorized?(**attributes)
        authorize attributes[self.class.record_key], :update?
      end

      def resolve(**attributes)
        record = attributes[self.class.record_key]
        language = attributes[:language] || I18n.locale
        Mobility.with_locale(language) do
          record.update(name: attributes[:name]) if attributes.key?(:name)
          {
            self.class.record_key => record,
            errors: errors_from_active_record(record.errors)
          }
        end
      end
    end
  end
end
