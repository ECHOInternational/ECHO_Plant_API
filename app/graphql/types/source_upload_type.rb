# frozen_string_literal: true

module Types
  # Ephemeral payload returned by createSourceUpload: where and how to PUT one object.
  class SourceUploadType < Types::BaseObject
    description 'Presigned S3 upload credentials for one data-source object PUT.'

    field :upload_url, String,
          null: false,
          description: 'Presigned S3 PUT URL, bound to the content type. Valid for 15 minutes.'

    field :bucket, String,
          null: false,
          description: 'S3 bucket the object will be written to.'

    field :key, String,
          null: false,
          description: 'S3 key the object will be stored under; deterministic from the source, kind and name.'

    field :expires_at, GraphQL::Types::ISO8601DateTime,
          null: false,
          description: 'When the presigned URL stops working.'
  end
end
