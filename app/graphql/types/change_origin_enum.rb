# frozen_string_literal: true

module Types
  # Where a recorded change came from.
  class ChangeOriginEnum < Types::BaseEnum
    graphql_name 'ChangeOrigin'
    description 'Where a recorded change came from. Entries written before provenance metadata existed report API.'

    value 'API', value: 'api', description: 'A request through the GraphQL API.'
    value 'SYNC', value: 'sync', description: 'An external data source synchronization run.'
    value 'BACKFILL', value: 'backfill', description: 'A maintenance backfill.'
  end
end
