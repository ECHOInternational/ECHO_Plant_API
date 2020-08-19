# frozen_string_literal: true

module Types
  # Defines fields for a variety
  class VarietyType < Types::BaseObject # rubocop:disable Metrics/ClassLength
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A variety represents a more precisely defined subgroup of plants with a common set of characteristics.'

    field :name, String,
          description: 'A translated Name for a Variety',
          null: true
    field :plant, Types::PlantType,
          description: 'The plant to which this variety belongs',
          null: true
    field :tolerances, Types::ToleranceType::ToleranceConnectionWithTotalCountType,
          description: 'A list of tolerances related to a variety',
          null: true,
          connection: true
    field :antinutrients, Types::AntinutrientType::AntinutrientConnectionWithTotalCountType,
          description: 'A list of antinutrients related to a variety',
          null: true,
          connection: true
    field :growth_habits, Types::GrowthHabitType::GrowthHabitConnectionWithTotalCountType,
          description: 'A list of growth habits related to a variety',
          null: true,
          connection: true
    field :uuid, ID,
          description: 'The internal database ID for a variety',
          null: false,
          method: :id
    field :has_edible_green_leaves, Boolean,
          description: 'Indicates whether or not a variety has edible green leaves',
          null: true
    field :has_edible_immature_fruit, Boolean,
          description: 'Indicates whether or not a variety has edible immature fruit',
          null: true
    field :has_edible_mature_fruit, Boolean,
          description: 'Indicates whether or not a variety has edible mature fruit',
          null: true
    field :can_be_used_for_fodder, Boolean,
          description: 'Indicates whether or not a variety can be used for fodder',
          null: true
    field :early_growth_phase, Types::EarlyGrowthPhaseEnum,
          description: 'Describes how vigorously a variety grows during early growth stages',
          null: true
    field :life_cycle, Types::LifeCycleEnum,
          description: 'Describes how long a variety takes to complete their entire life cycle',
          null: true
    field :n_accumulation_range, String,
          description: 'Describes how much nitrogren a variety may accumulate in kilograms of nitrogen per hectare',
          null: true
    field :biomass_production_range, String,
          description: 'Describes how much biomass a variety may produce in kilograms per hectare',
          null: true
    field :optimal_temperature_range, String,
          description: 'Describes the optimal range of temperatures for a variety in degrees celsius',
          null: true
    field :optimal_rainfall_range, String,
          description: 'Describes the optimal range of rainfall needed for a variety in mm',
          null: true
    field :seasonality_days_range, String,
          description: 'Describes a range of the number of days to maturity or havest',
          null: true
    field :optimal_altitude_range, String,
          description: 'Describes the optimal range of altitudes for a variety in meters',
          null: true
    field :ph_range, String,
          description: 'Describes the optimal range of soil pH for a variety',
          null: true
    field :description, String,
          description: 'A translated description of a variety',
          null: true
    field :created_by, String,
          description: "The user ID of a variety's creator",
          null: true
    field :owned_by, String,
          description: "The user ID of a variety's owner",
          null: true
    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a variety',
          null: true
    field :translations, [Types::VarietyType::VarietyTranslationType],
          description: 'Translations of translatable variety fields',
          null: false,
          method: :translations_array
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the variety. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
          null: false
    field :description, String,
          description: 'A translated description of a variety',
          null: true
    field :info_sheet_description, String,
          description: 'A translated description suitable for an ECHO Variety information sheet',
          null: true
    field :origin, String,
          description: 'A translated description of the origin of a variety',
          null: true
    field :uses, String,
          description: 'A translated description of the uses for a variety',
          null: true
    field :cultivation, String,
          description: 'A translated set of instructions for the cultivation of a variety',
          null: true
    field :harvesting_and_seed_production, String,
          description: 'A translated descripion on the harvesting and seed production of a variety',
          null: true
    field :pests_and_diseases, String,
          description: 'A translated description of common pests and diseases of a variety',
          null: true
    field :cooking_and_nutrition, String,
          description: 'A translated description of cooking and nutrition data for a variety',
          null: true
    field :attribution, String,
          description: 'A translated attribution statement for the data stored for a variety',
          null: true
    field :edible_green_leaves_note, String,
          description: 'Translated full text description of whther or not a variety has edible green leaves',
          null: true
    field :edible_immature_fruit_note, String,
          description: 'Translated full text description of whether or not a variety has edible immature fruit',
          null: true
    field :edible_mature_fruit_note, String,
          description: 'Translated full text description of whether or not a variety has edible mature fruit',
          null: true
    field :used_for_fodder_note, String,
          description: 'Translated full text description of whether or not the variety can be used for fodder',
          null: true
    field :tolerance_note, String,
          description: 'Translated full text description of tolerances related to a variety',
          null: true
    field :antinutrient_note, String,
          description: 'Translated full text description of antinutrients related to a variety',
          null: true
    field :seeding_rate, String,
          description: 'Translated information about the seeding rate for a variety',
          null: true
    field :planting_instructions, String,
          description: 'Translated varietying instructions for a variety',
          null: true
    field :asia_regional_info, String,
          description: 'Translated information about a variety that is specifically relevant to Asia',
          null: true
    field :life_cycle_note, String,
          description: "Translated full text description of the variety's life cycle",
          null: true
    field :n_accumulation_note, String,
          description: 'Translated full text description of the capacity for nitrogen accumulation for variety',
          null: true
    field :biomass_production_note, String,
          description: 'Translated full text description of the data held in the biomass production attribute',
          null: true
    field :optimal_temperature_note, String,
          description: "Translated full text description of a plan's optimal temperature range",
          null: true
    field :optimal_rainfall_note, String,
          description: "Translated full text description of a variety's rainfall needs",
          null: true
    field :seasonality_note, String,
          description: "Translated full text description of a variety's seasonal cycle",
          null: true
    field :early_growth_phase_note, String,
          description: 'Translated full text description of the early growth phase of a variety',
          null: true
    field :altitude_note, String,
          description: 'Translated full text description of the altitude attributes of a variety',
          null: true
    field :ph_note, String,
          description: 'Translated full text description of the ph attributes of a variety',
          null: true
    field :growth_habits_note, String,
          description: 'Translated full text description of the growth habits for a variety',
          null: true
    # field :versions, Types::VarietyType::VarietyVersionConnectionWithTotalCountType, null: false, connection: true

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end

    def visibility
      @object.visibility.to_sym
    end

    # def versions
    # @object.translation.versions.where(event: "update").reorder('created_at DESC')
    # end
  end
end
