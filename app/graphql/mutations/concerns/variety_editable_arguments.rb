# frozen_string_literal: true

module Mutations
  module Concerns
    # Declares the shared editable arguments for variety create/update mutations.
    # `name` and `description` are declared on the mutations themselves.
    module VarietyEditableArguments
      TRANSLATABLE_FIELDS = %i[
        info_sheet_description origin uses cultivation harvesting_and_seed_production
        pests_and_diseases cooking_and_nutrition attribution edible_green_leaves_note
        edible_immature_fruit_note edible_mature_fruit_note used_for_fodder_note
        tolerance_note antinutrient_note seeding_rate planting_instructions
        asia_regional_info life_cycle_note n_accumulation_note biomass_production_note
        optimal_temperature_note optimal_rainfall_note seasonality_note
        early_growth_phase_note altitude_note ph_note growth_habits_note
      ].freeze

      BOOLEAN_FIELDS = %i[
        has_edible_green_leaves has_edible_immature_fruit
        has_edible_mature_fruit can_be_used_for_fodder
      ].freeze

      def self.included(base)
        TRANSLATABLE_FIELDS.each do |name|
          base.argument name, String, required: false,
                                      description: "The translatable #{name.to_s.humanize.downcase} of the variety"
        end
        BOOLEAN_FIELDS.each do |name|
          base.argument name, GraphQL::Types::Boolean, required: false
        end
        RangeLiteralValidation::RANGE_FIELDS.each do |name|
          base.argument name, String, required: false,
                                      description: 'Postgres range literal, e.g. "[0,10]"'
        end
      end
    end
  end
end
