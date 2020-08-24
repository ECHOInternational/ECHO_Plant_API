# frozen_string_literal: true

module Types
  # An enumerator for units
  class UnitEnum < Types::BaseEnum
    graphql_name 'Unit'
    description 'Indicates the unit of associated values'
    value 'WEIGHT',
          value: 'weight',
          description: 'Indicates associated values are in kilograms'
    value 'COUNT',
          value: 'count',
          description: 'Indicates associated values are single units'
  end
end
