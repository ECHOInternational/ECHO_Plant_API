# frozen_string_literal: true

module Mutations
  module Relations
    # Base mutation for set-style lookup relation updates on owned records
    # (plant/variety <-> categories/tolerances/growth habits/antinutrients).
    # The supplied id list replaces the association entirely.
    class UpdateRelationsBaseMutation < BaseMutation
      class << self
        attr_reader :owner_key, :association

        def relates(owner_class, type:, association:, items_type:)
          @owner_key = owner_class.name.underscore.to_sym
          @association = association
          argument "#{@owner_key}_id".to_sym, GraphQL::Types::ID, required: true, loads: type
          argument "#{association.to_s.singularize}_ids".to_sym, [GraphQL::Types::ID],
                   required: true,
                   loads: items_type,
                   as: association,
                   description: "Replaces the #{association} set. An empty list clears it."
          field @owner_key, type, null: true
          field :errors, [Types::MutationError], null: false
        end
      end

      def authorized?(**attributes)
        authorize attributes[self.class.owner_key], :update?
      end

      def resolve(**attributes)
        owner = attributes[self.class.owner_key]
        items = attributes[self.class.association]
        owner.public_send("#{self.class.association}=", items)
        {
          self.class.owner_key => owner,
          errors: errors_from_active_record(owner.errors)
        }
      end
    end
  end
end
