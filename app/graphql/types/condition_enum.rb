# frozen_string_literal: true

module Types
  # An enumerator for basic quality values
  class ConditionEnum < Types::BaseEnum
    graphql_name 'Condition'
    description 'Describes the quality or condition of something'
    value 'POOR',
          value: 'poor'
    value 'FAIR',
          value: 'fair'
    value 'GOOD',
          value: 'good'
  end
end
