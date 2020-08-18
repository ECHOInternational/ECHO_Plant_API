# frozen_string_literal: true

module Types
  class PlantType
    # Defines translated fields for a plant
    class PlantTranslationType < Types::BaseObject
      description 'Translated fields for a Plant'
      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :description, String,
            description: 'A translated description of a plant',
            null: true
      field :info_sheet_description, String,
            description: 'A translated description suitable for an ECHO Plant information sheet',
            null: true
      field :origin, String,
            description: 'A translated description of the origin of a plant',
            null: true
      field :uses, String,
            description: 'A translated description of the uses for a plant',
            null: true
      field :cultivation, String,
            description: 'A translated set of instructions for the cultivation of a plant',
            null: true
      field :harvesting_and_seed_production, String,
            description: 'A translated descripion on the harvesting and seed production of a plant',
            null: true
      field :pests_and_diseases, String,
            description: 'A translated description of common pests and diseases of a plant',
            null: true
      field :cooking_and_nutrition, String,
            description: 'A translated description of cooking and nutrition data for a plant',
            null: true
      # field :varieties, String,
      #       description: 'A translated description of the varieties of a plant',
      #       null: true
      field :attribution, String,
            description: 'A translated attribution statement for the data stored for a plant',
            null: true
      field :edible_green_leaves_note, String,
            description: 'Translated full text description of whther or not a plant has edible green leaves',
            null: true
      field :edible_immature_fruit_note, String, 
            description: 'Translated full text description of whether or not a plant has edible immature fruit',
            null: true
      field :edible_mature_fruit_note, String,
            description: 'Translated full text description of whether or not a plant has edible mature fruit',
            null: true
      field :used_for_fodder_note, String,
            description: 'Translated full text description of whether or not the plant can be used for fodder',
            null: true
      field :tolerance_note, String,
            description: 'Translated full text description of tolerances related to a plant',
            null: true
      field :antinutrient_note, String,
            description: 'Translated full text description of antinutrients related to a plant',
            null: true
      field :seeding_rate, String,
            description: 'Translated information about the seeding rate for a plant',
            null: true
      field :planting_instructions, String,
            description: 'Translated planting instructions for a plant',
            null: true
      field :asia_regional_info, String,
            description: 'Translated information about a plant that is specifically relevant to Asia',
            null: true
      field :life_cycle_note, String,
            description: "Translated full text description of the plant's life cycle",
            null: true
      field :n_accumulation_note, String,
            description: 'Translated full text description of the capacity for nitrogen accumulation for plant',
            null: true
      field :biomass_production_note, String,
            description: 'Translated full text description of the data held in the biomass production attribute',
            null: true
      field :optimal_temperature_note, String,
            description: "Translated full text description of a plan's optimal temperature range",
            null: true
      field :optimal_rainfall_note, String,
            description: "Translated full text description of a plant's rainfall needs",
            null: true
      field :seasonality_note, String,
            description: "Translated full text description of a plant's seasonal cycle",
            null: true
      field :early_growth_phase_note, String,
            description: 'Translated full text description of the early growth phase of a plant',
            null: true
      field :altitude_note, String,
            description: 'Translated full text description of the altitude attributes of a plant',
            null: true
      field :ph_note, String,
            description: 'Translated full text description of the ph attributes of a plant',
            null: true
      field :growth_habits_note, String,
            description: 'Translated full text description of the growth habits for a plant',
            null: true
    end
  end
end
