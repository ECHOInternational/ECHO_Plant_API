# frozen_string_literal: true

module Mutations
  module Lookups
    # Base mutation for creating simple translatable lookup records
    # (Tolerance, GrowthHabit, Antinutrient, ImageAttribute).
    # Subclasses declare their model with `lookup_model`.
    class CreateLookupBaseMutation < BaseMutation
      class << self
        attr_reader :model_class, :record_key

        def lookup_model(klass, type:)
          @model_class = klass
          @record_key = klass.name.underscore.to_sym
          argument :name, String,
                   required: true,
                   description: "The translatable name of the #{klass.name.titleize.downcase}"
          argument :language, String,
                   required: false,
                   description: 'Language of the translatable fields supplied'
          field record_key, type, null: true
          field :errors, [Types::MutationError], null: false
        end
      end

      def authorized?(**_attributes)
        authorize self.class.model_class, :create?
      end

      def resolve(**attributes)
        language = attributes[:language] || I18n.locale
        Mobility.with_locale(language) do
          record = self.class.model_class.new(name: attributes[:name])
          result = record.save
          {
            self.class.record_key => result ? record : nil,
            errors: errors_from_active_record(record.errors)
          }
        end
      end
    end
  end
end
