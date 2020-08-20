# frozen_string_literal: true

module Types
  # An enumerator for soil quality values
  class SoilQualityEnum < Types::BaseEnum
    graphql_name 'SoilQuality'
    description 'Describes the quaility of soil'
    value 'POOR',
          value: 'poor'
    value 'FAIR',
          value: 'fair'
    value 'GOOD',
          value: 'good'
  end
end
