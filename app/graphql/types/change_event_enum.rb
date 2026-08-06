# frozen_string_literal: true

module Types
  # The kind of change a history entry records.
  class ChangeEventEnum < Types::BaseEnum
    graphql_name 'ChangeEvent'
    description 'The kind of change a record history entry represents.'

    value 'CREATED', value: 'created', description: 'The row was created.'
    value 'UPDATED', value: 'updated', description: 'The row was updated.'
    value 'DELETED', value: 'deleted', description: 'The row was deleted.'
    value 'RESTORED', value: 'restored', description: 'The record was restored to an earlier state.'
  end
end
