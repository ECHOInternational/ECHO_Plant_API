# frozen_string_literal: true

# The ECHOcommunity data source, and the set of attributes it governs.
#
# `data_sources` has no column for the managed attribute set, so it has to live
# in code — and it has to be STABLE. `SourceSynchronizer` slices both the
# incoming row and the stored snapshot to this list before digesting them, so
# adding or removing an entry silently changes the meaning of every digest
# already on disk and makes the next run score unrelated records as changed.
# Treat this list as a schema.
#
# Two consequences for whoever writes the feed:
#
#   * every row must supply EVERY key here, using '' for absent text. A missing
#     key is not "unchanged" — it changes the digest and reads as an edit.
#   * only translated narrative text is here. Ranges and boolean flags are
#     deliberately excluded: they are not translated, ECHOcommunity stores
#     defaults as data (the 0–14 pH problem), and mixing them in would put a
#     placeholder-versus-NULL argument inside the same digest as real prose.
#     They get their own pass.
module EcDataSource
  NAME = 'ECHOcommunity'
  SOURCE_SYSTEM_KEY = 'echocommunity'

  # API attribute names, not ECHOcommunity's. The one non-obvious mapping is
  # D-025: ECHOcommunity's plants.description (the long narrative) is this
  # application's info_sheet_description, while its resources.description (the
  # short summary) is this application's description.
  PLANT_ATTRIBUTES = %w[
    description
    info_sheet_description
    origin
    uses
    cultivation
    harvesting_and_seed_production
    pests_and_diseases
    cooking_and_nutrition
    attribution
    asia_regional_info
    seeding_rate
    antinutrient_note
    tolerance_note
    used_for_fodder_note
    edible_green_leaves_note
    edible_mature_fruit_note
    optimal_temperature_note
  ].freeze

  class << self
    # Idempotent. The owning organization is ECHO itself: the data source
    # belongs to the organization whose records it carries.
    def find_or_create!(organization:)
      DataSource.find_or_create_by!(source_system_key: SOURCE_SYSTEM_KEY) do |ds|
        ds.name = NAME
        ds.organization = organization
        ds.notes = 'Plant data migrated from echocommunity.org. See the ' \
                   'migration workspace decision log, D-002 and D-041.'
      end
    end

    def existing
      DataSource.find_by(source_system_key: SOURCE_SYSTEM_KEY)
    end
  end
end
