# frozen_string_literal: true

# The Food Plants International data source, and the set of attributes it
# governs (fpi-connector schema-delta item 1; decisions 18, 19, 29, 40, 45, 46).
#
# Like EcDataSource, this list is a schema: SourceSynchronizer slices both the
# incoming row and the stored snapshot to it before digesting, so adding or
# removing a key changes the meaning of every digest on disk. Bump
# PLANT_ATTRIBUTES_VERSION on any change and run fpi:rebaseline (item 2),
# which uses EMPTY_VALUES as the base value of a key the source has never sent.
#
# Unlike EcDataSource, the list carries identity (scientific_name,
# family_names, family_id, scientific_name_authority), the safety concept, and
# two relation sets, not only prose: FPI is a recurring source, and a curator's
# correction to a name that is left out of the set could never be reconciled
# against Bruce's rename. Every value travels as a String -- '' for absent text,
# 'true'/'false' for booleans, a lower-case UUID or '' for family_id, and the
# canonical JSON-array string of each relation set -- so the digest on both
# sides is computed from the same bytes.
module FpiDataSource
  NAME = 'Food Plants International'
  SOURCE_SYSTEM_KEY = 'fpi'
  # The ECHOcommunity IdP organization that owns FPI's records (decision 41).
  DEFAULT_ORGANIZATION_ID = 'b7ab3117-e610-4b7d-b097-a51ebe911d79'

  PLANT_ATTRIBUTES_VERSION = 1
  PLANT_ATTRIBUTES = %w[
    scientific_name family_names family_id scientific_name_authority
    description uses cultivation attribution
    harvesting_and_seed_production planting_instructions habitat notes
    safety_level safety_note edibility_uncertain
    common_name_set category_set
  ].freeze

  # The base value of a key upstream has never sent (item 2). Every other key: ''.
  EMPTY_VALUES = {
    'safety_level' => 'none',
    'edibility_uncertain' => 'false',
    'common_name_set' => RelationSets::CommonNames.empty,
    'category_set' => RelationSets::Categories.empty
  }.freeze

  RELATION_SETS = {
    'common_name_set' => RelationSets::CommonNames,
    'category_set' => RelationSets::Categories
  }.freeze

  class << self
    def empty_value(attribute)
      EMPTY_VALUES.fetch(attribute, '')
    end

    # Idempotent. The owning organization is FPI's own, mirrored from the IdP.
    def find_or_create!(organization:)
      DataSource.find_or_create_by!(source_system_key: SOURCE_SYSTEM_KEY) do |ds|
        ds.name = NAME
        ds.organization = organization
        ds.notes = 'Plant data synchronised from the Food Plants International database ' \
                   '(French, B.R. & Maynard, A.R.), delivered as FileMaker snapshots and ' \
                   'transformed by the fpi-connector. Attribution travels on each record.'
      end
    end

    def existing
      DataSource.find_by(source_system_key: SOURCE_SYSTEM_KEY)
    end
  end
end
