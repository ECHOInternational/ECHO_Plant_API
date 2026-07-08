# frozen_string_literal: true

module Mutations
  # Returns a presigned S3 PUT URL so clients can upload image files directly.
  # The returned imageId should be passed to createImage once the upload completes.
  class CreateUpload < BaseMutation
    argument :filename, String,
             required: true,
             description: 'Original filename of the file to be uploaded (used to derive the S3 key).'

    argument :content_type, String,
             required: true,
             description: 'MIME content type of the file (e.g. "image/jpeg"). Bound to the presigned URL.'

    field :upload, Types::UploadType, null: true
    field :errors, [Types::MutationError], null: false

    # Requires write access via the existing UploadPolicy#show?.
    # Pundit resolves UploadPolicy from the :upload symbol.
    def authorized?(**_attributes)
      authorize :upload, :show?
    end

    def resolve(filename:, content_type:)
      image_id = SecureRandom.uuid
      bucket = ENV.fetch('IMAGES_S3_BUCKET', 'images-us-east-1.echocommunity.org')
      key = "uploads/#{image_id}/#{sanitize_filename(filename)}"

      {
        upload: {
          image_id: image_id,
          upload_url: presigned_put_url(bucket, key, content_type),
          bucket: bucket,
          key: key
        },
        errors: []
      }
    end

    private

    # Strip any leading path components so filenames like "../evil/../a b.jpg"
    # cannot escape the uploads/<uuid>/ prefix.
    def sanitize_filename(filename)
      File.basename(filename)
    end

    def presigned_put_url(bucket, key, content_type)
      Aws::S3::Presigner.new.presigned_url(
        :put_object,
        bucket: bucket,
        key: key,
        content_type: content_type,
        expires_in: 15 * 60
      )
    end
  end
end
