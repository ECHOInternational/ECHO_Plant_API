# frozen_string_literal: true

module Types
  # A reuseable enumerator Early Growth Phase Speed Values
  class EarlyGrowthPhaseEnum < Types::BaseEnum
    graphql_name 'EarlyGrowthPhaseSpeed'
    description 'Describes how vigorously a plant grows during early growth stages'
    value 'SLOW',
          value: 'slow',
          description: 'Plant grows less vigorously than other similar plants'
    value 'INTERMEDIATE',
          value: 'intermediate'
    value 'FAST',
          value: 'fast',
          description: 'Plant grows more vigorously than other similar plants'
  end
end
