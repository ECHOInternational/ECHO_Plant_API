# frozen_string_literal: true

module Types
  # What a data-source upload carries, which decides its bucket and key prefix.
  class SourceUploadKindEnum < Types::BaseEnum
    graphql_name 'SourceUploadKind'
    description 'The kind of file a data source is delivering.'
    value 'PAYLOAD', value: 'payload',
                     description: 'A sync payload file (a shard, deletions, or manifest), stored privately under <source>/payloads/.'
    value 'PHOTO', value: 'photo',
                   description: 'A source photograph, stored under <source>/photos/ in the images bucket.'
    value 'DRAWING', value: 'drawing',
                     description: 'A source drawing, stored under <source>/drawings/ in the images bucket.'
  end
end
