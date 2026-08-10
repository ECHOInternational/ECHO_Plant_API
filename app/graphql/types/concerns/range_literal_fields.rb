# frozen_string_literal: true

module Types
  module Concerns
    # Resolver methods for the 7 numeric-range fields shared by PlantType and
    # VarietyType. The `field :x_range, String, ...` declarations already
    # exist on each including type; this concern only supplies the resolver
    # methods, so every range field renders through RangeLiteral.serialize --
    # the same canonical bracket-literal format
    # (Mutations::Concerns::RangeLiteralValidation) that create/update
    # mutations accept -- instead of graphql-ruby's default String
    # coercion, which falls back to Ruby's Range#to_s ("5.5..7.0",
    # "0...Infinity").
    #
    # Sources the field list from RangeLiteralValidation::RANGE_FIELDS so
    # there is exactly one list of "the 7 range fields" in the codebase.
    module RangeLiteralFields
      extend ActiveSupport::Concern

      included do
        Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.each do |field|
          define_method(field) do
            RangeLiteral.serialize(object.public_send(field))
          end
        end
      end
    end
  end
end
