# frozen_string_literal: true

# The single source of truth for which columns may be staged in a draft and
# restored from a version.
#
# ChangeHistory::Restorer and RecordDraft both consume this. They used to carry
# separate lists, and the copies drifted: family_id was added to plants when
# botanical families landed, and the restore whitelist was never extended, so
# restoring a version silently left the family assignment untouched.
#
# Deliberately excludes every ownership, provenance and workflow column.
# Visibility is changed through its own mutation arguments and is never staged:
# publishing a draft is what changes publication state.
module DraftableAttributes
  module_function

  PLANT = (
    %w[scientific_name family_names family_id early_growth_phase life_cycle translations] +
    Mutations::Concerns::PlantEditableArguments::BOOLEAN_FIELDS.map(&:to_s) +
    Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.map(&:to_s)
  ).freeze

  VARIETY = (
    %w[translations] +
    Mutations::Concerns::VarietyEditableArguments::BOOLEAN_FIELDS.map(&:to_s) +
    Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.map(&:to_s)
  ).freeze

  FAMILY = %w[translations storage_physiology seed_longevity seed_banking_rank].freeze

  CATEGORY = %w[translations].freeze

  BY_MODEL = {
    'Plant' => PLANT, 'Variety' => VARIETY, 'Family' => FAMILY, 'Category' => CATEGORY
  }.freeze

  def for(model_class)
    BY_MODEL.fetch(model_class.name)
  end
end
