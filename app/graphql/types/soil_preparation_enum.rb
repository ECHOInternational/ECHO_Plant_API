# frozen_string_literal: true

module Types
  # An enumerator for soil preparation types
  class SoilPreparationEnum < Types::BaseEnum
    graphql_name 'SoilPreparation'
    description 'Indicates a type of soil preparation.'
    value 'GREENHOUSE',
          value: 'greenhouse'
    value 'PLANTING_STATION',
          value: 'planting_station'
    value 'NO_TILL',
          value: 'no_till'
    value 'FULL_TILL',
          value: 'full_till'
    value 'RAISED_BEDS',
          value: 'raised_beds'
    value 'VERTICAL_GARDEN',
          value: 'vertical_garden'
    value 'CONTAINER',
          value: 'container'
    value 'OTHER',
          value: 'other'
  end
end
