# frozen_string_literal: true

module Types
  # What a data-source download reads, which decides its key prefix.
  class SourceDownloadKindEnum < Types::BaseEnum
    graphql_name 'SourceDownloadKind'
    description 'The kind of file a data source is reading back.'
    value 'OUTCOME', value: 'outcome',
                     description: 'An applied run\'s outcome file (outcomes.jsonl or summary.json), stored privately under <source>/outcomes/<run_id>/.'
  end
end
