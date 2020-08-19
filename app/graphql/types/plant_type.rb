# frozen_string_literal: true

module Types
  # Defines fields for a plant
  class PlantType < Types::BaseObject # rubocop:disable Metrics/ClassLength
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A plant is a crop species available through the Plant API.'

    field :primary_common_name, String,
          description: 'A common name for the plant in the current language requested (if available).',
          null: true
    field :common_names, Types::CommonNameType.connection_type,
          description: 'Language specific names for a plant',
          null: true
    field :tolerances, Types::ToleranceType::ToleranceConnectionWithTotalCountType,
          description: 'A list of tolerances related to a plant',
          null: true,
          connection: true
    field :antinutrients, Types::AntinutrientType::AntinutrientConnectionWithTotalCountType,
          description: 'A list of antinutrients related to a plant',
          null: true,
          connection: true
    field :growth_habits, Types::GrowthHabitType::GrowthHabitConnectionWithTotalCountType,
          description: 'A list of growth habits related to a plant',
          null: true,
          connection: true
    field :categories, Types::CategoryType::CategoryConnectionWithTotalCountType,
          description: 'A list of categories to which a plant belongs',
          null: true,
          connection: true
    field :varieties, Types::VarietyType::VarietyConnectionWithTotalCountType,
          null: true,
          connection: true
    field :uuid, ID,
          description: 'The internal database ID for a plant',
          null: false,
          method: :id
    field :scientific_name, String,
          description: 'The scientific name for a plant (always render italicized)',
          null: false
    field :family_names, String,
          description: 'The family names for a plant',
          null: true
    field :genus, String,
          description: 'The genus of a plant',
          null: true
    field :has_edible_green_leaves, Boolean,
          description: 'Indicates whether or not a plant has edible green leaves',
          null: true
    field :has_edible_immature_fruit, Boolean,
          description: 'Indicates whether or not a plant has edible immature fruit',
          null: true
    field :has_edible_mature_fruit, Boolean,
          description: 'Indicates whether or not a plant has edible mature fruit',
          null: true
    field :can_be_used_for_fodder, Boolean,
          description: 'Indicates whether or not a plant can be used for fodder',
          null: true
    field :early_growth_phase, Types::EarlyGrowthPhaseEnum,
          description: 'Describes how vigorously a plant grows during early growth stages',
          null: true
    field :life_cycle, Types::LifeCycleEnum,
          description: 'Describes how long a plant takes to complete their entire life cycle',
          null: true
    field :n_accumulation_range, String,
          description: 'Describes how much nitrogren a plant may accumulate in tonnes per hectare',
          null: true
    field :biomass_production_range, String,
          description: 'Describes how much biomass a plant may produce in kilograms of nitrogen per hectare',
          null: true
    field :optimal_temperature_range, String,
          description: 'Describes the optimal range of temperatures for a plant in degrees celsius',
          null: true
    field :optimal_rainfall_range, String,
          description: 'Describes the optimal range of rainfall needed for a plant in mm',
          null: true
    field :seasonality_days_range, String,
          description: 'Describes a range of the number of days to maturity or havest',
          null: true
    field :optimal_altitude_range, String,
          description: 'Describes the optimal range of altitudes for a plant in meters',
          null: true
    field :ph_range, String,
          description: 'Describes the optimal range of soil pH for a plant',
          null: true
    # Translated Fields
    field :description, String,
          description: 'A translated description of a plant',
          null: true
    field :created_by, String,
          description: "The user ID of a plant's creator",
          null: true
    field :owned_by, String,
          description: "The user ID of a plant's owner",
          null: true
    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a plant',
          null: true
    field :translations, [Types::PlantType::PlantTranslationType],
          description: 'Translations of translatable plant fields',
          null: false,
          method: :translations_array
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the plant. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
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
    # field :versions, Types::PlantType::PlantVersionConnectionWithTotalCountType, null: false, connection: true

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end

    def visibility
      @object.visibility.to_sym
    end

    def categories
      Pundit.policy_scope(context[:current_user], @object.categories)
    end

    def varieties
      Pundit.policy_scope(context[:current_user], @object.varieties)
    end

    # def versions
    # @object.translation.versions.where(event: "update").reorder('created_at DESC')
    # end
  end
end
