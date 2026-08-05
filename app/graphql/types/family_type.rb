# frozen_string_literal: true

module Types
  # Defines fields for a botanical, fungal or algal family.
  class FamilyType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A family is a rank of biological classification, sourced from ' \
                'the Catalogue of Life. The list is fixed; only its metadata is editable.'

    field :uuid, ID,
          description: 'The internal database ID for a family',
          null: false,
          method: :id
    field :name, String,
          description: 'The scientific name of the family. Not translated.',
          null: false
    field :kingdom, String,
          description: 'Plantae, Fungi or Chromista',
          null: false
    field :plant_type, String,
          description: 'Broad grouping derived from the source classification, ' \
                       'for example Angiosperms or Ferns & Fern Allies',
          null: true
    field :status, String,
          description: 'accepted, or superseded when the source taxonomy has merged ' \
                       'this family into another',
          null: false
    field :superseded_by, Types::FamilyType,
          description: 'The family this one was merged into, when status is superseded',
          null: true
    field :col_id, String,
          description: 'Catalogue of Life identifier. Informational only: these are ' \
                       'not stable across releases and nothing references them.',
          null: true
    field :classification_version, String,
          description: 'The source release this row was loaded from',
          null: false
    field :snapshot_date, GraphQL::Types::ISO8601Date,
          description: 'The date of the source release',
          null: false

    field :description, String,
          description: 'The translated description of a family',
          null: true
    field :seed_banking_notes, String,
          description: 'Translated notes on this family suitability for seed banking',
          null: true
    field :storage_physiology, String,
          description: 'orthodox, recalcitrant, intermediate, variable, mixed or unknown',
          null: true
    field :seed_longevity, String,
          description: 'low, low_medium, medium, medium_high or high',
          null: true
    field :seed_banking_rank, Integer,
          description: 'Seed banking suitability from 1 (poor) to 5 (excellent)',
          null: true

    field :translations, [Types::FamilyType::FamilyTranslationType],
          description: 'Translations of translatable family fields',
          null: false,
          method: :translations_array
  end
end
