# frozen_string_literal: true

module Types
  # Defines fields for a Köppen-Geiger climate zone.
  class KoppenZoneType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A Köppen-Geiger climate zone. The list is fixed; only the ' \
                'translated name and description are editable.'

    field :uuid, ID,
          description: 'The internal database ID for a climate zone',
          null: false,
          method: :id
    field :code, String,
          description: 'The Köppen code, for example Cfa. Not translated: codes are ' \
                       'defined by the classification and do not change.',
          null: false
    field :level, String,
          description: 'group (A-E), subgroup (Cf, BS, ...) or class (Cfa, BSh, ...)',
          null: false
    field :authoritative, Boolean,
          description: 'True when this zone appears in Beck et al. 2018, the published ' \
                       'map legend: the 5 groups and 30 classes. The 8 subgroups are an ' \
                       'ECHO intermediate level, and BSn/BWn record frequent fog, which ' \
                       'map rasters do not resolve. False is a statement about the map ' \
                       'product, not about legitimacy.',
          null: false
    field :parent, Types::KoppenZoneType,
          description: 'The zone one level up: Cfa -> Cf -> C',
          null: true
    field :children, [Types::KoppenZoneType],
          description: 'The zones one level down',
          null: false
    field :classification_source, String,
          description: 'The classification this row was modelled on',
          null: false
    field :classification_version, String,
          description: 'The source release this row was loaded from',
          null: false
    field :snapshot_date, GraphQL::Types::ISO8601Date,
          description: 'The date of the source release',
          null: false
    field :name, String,
          description: 'The translated name of a climate zone',
          null: true
    field :description, String,
          description: 'The translated description of a climate zone',
          null: true
    field :translations, [Types::KoppenZoneType::KoppenZoneTranslationType],
          description: 'Translations of translatable climate zone fields',
          null: false,
          method: :translations_array

    # Ordered so a client rendering the tree gets a stable sequence without
    # sorting client-side; id breaks ties as elsewhere.
    def children
      object.children.order(:position).order(:id)
    end
  end
end
