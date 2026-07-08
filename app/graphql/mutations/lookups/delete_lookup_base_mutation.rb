# frozen_string_literal: true

module Mutations
  module Lookups
    # Base mutation for deleting simple lookup records.
    # Subclasses declare their model with `lookup_model`.
    class DeleteLookupBaseMutation < BaseMutation
      class << self
        attr_reader :model_class, :record_key, :id_key

        def lookup_model(klass, type:)
          @model_class = klass
          @record_key = klass.name.underscore.to_sym
          @id_key = "#{klass.name.underscore}_id".to_sym
          argument id_key, GraphQL::Types::ID,
                   required: true,
                   loads: type,
                   description: "The #{klass.name.titleize.downcase} to be deleted"
          field id_key, GraphQL::Types::ID, null: true
          field :errors, [Types::MutationError], null: false
        end
      end

      def authorized?(**attributes)
        authorize attributes[self.class.record_key], :destroy?
      end

      def resolve(**attributes)
        record = attributes[self.class.record_key]
        id = PlantApiSchema.id_from_object(record, self.class.model_class, {})
        result = record.destroy
        {
          self.class.id_key => result ? id : nil,
          errors: errors_from_active_record(record.errors)
        }
      end
    end
  end
end
