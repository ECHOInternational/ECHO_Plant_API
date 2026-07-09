# frozen_string_literal: true

module Types
  # Ephemeral payload type returned by the createUpload mutation.
  # Contains the information a client needs to PUT a file directly to S3.
  class UploadType < Types::BaseObject
    description 'Presigned S3 upload credentials for a single object PUT.'

    field :image_id, ID,
          null: false,
          description: 'UUID to use as the imageId when calling createImage after the upload completes.'

    field :upload_url, String,
          null: false,
          description: 'Presigned S3 PUT URL. Valid for 15 minutes.'

    field :bucket, String,
          null: false,
          description: 'S3 bucket the object will be written to.'

    field :key, String,
          null: false,
          description: 'S3 key the object will be stored under.'
  end
end
