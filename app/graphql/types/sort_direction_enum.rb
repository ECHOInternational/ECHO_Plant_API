# frozen_string_literal: true

module Types
  # A reuseable enumerator for defining the direction that a query should be sorted.
  class SortDirectionEnum < Types::BaseEnum
    graphql_name 'SortDirection'
    description 'Sets the direction returned records will be sorted'
    value 'ASC', value: :asc, description: 'Ascending Order'
    value 'DESC', value: :desc, description: 'Descending Order'
  end
end
