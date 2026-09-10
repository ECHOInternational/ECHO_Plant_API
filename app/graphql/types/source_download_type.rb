# frozen_string_literal: true

module Types
  # Ephemeral payload returned by createSourceDownload: where and how to GET one object.
  class SourceDownloadType < Types::BaseObject
    description 'Presigned S3 download credentials for one data-source object GET.'

    field :download_url, String,
          null: false,
          description: 'Presigned S3 GET URL. Valid for 15 minutes.'

    field :bucket, String,
          null: false,
          description: 'S3 bucket the object lives in.'

    field :key, String,
          null: false,
          description: 'S3 key of the object; deterministic from the source, kind and name.'

    field :bytes, Integer,
          null: false,
          description: 'Size of the object, so the caller can check the download.'

    field :expires_at, GraphQL::Types::ISO8601DateTime,
          null: false,
          description: 'When the presigned URL stops working.'
  end
end
