# frozen_string_literal: true

module Mutations
  # Returns a presigned S3 PUT URL for a data-source file, so a connector can
  # deliver payload shards and source images without holding AWS credentials
  # (fpi-connector decisions 36 and 43).
  #
  # Keys are deterministic from the source, the kind and the name, so a
  # re-delivery overwrites the same object and an image's identity is its
  # source row (fpi/photos/<ROWID>.jpg). Payloads go to the private payloads
  # bucket, which the sync task reads; images go to the images bucket, which is
  # served publicly -- so an image upload is a publication and must wait for
  # the source's rights agreement (decision 36).
  #
  # Who: system superusers, and holders of the deliver_source_data capability
  # in the organization that owns the data source (stewards and org admins).
  class CreateSourceUpload < BaseMutation
    PAYLOAD_NAME = %r{\A[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*\z}
    IMAGE_NAME = /\A[0-9]+\.(?:jpe?g|png|gif|webp)\z/
    EXPIRY = 15.minutes

    argument :source_system_key, String, required: true,
                                         description: 'The data source delivering the file, e.g. "fpi".'
    argument :kind, Types::SourceUploadKindEnum, required: true
    argument :name, String, required: true,
                            description: 'Payload: a relative path such as "<run_id>/shard-000.json". Image: "<ROWID>.<ext>".'
    argument :content_type, String, required: true,
                                    description: 'MIME type of the file, bound to the presigned URL.'

    field :source_upload, Types::SourceUploadType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(source_system_key:, **_attributes)
      data_source = load_data_source!(source_system_key)
      user = context[:current_user]
      allowed = user&.system_superuser? ||
                user&.organization_capability?(data_source.organization_id, :deliver_source_data)
      return true if allowed

      raise Pundit::NotAuthorizedError.new(query: :deliver_source_data, record: data_source, policy: nil)
    end

    def resolve(source_system_key:, kind:, name:, content_type:)
      data_source = load_data_source!(source_system_key)
      bucket, key = destination(data_source, kind, name)
      {
        source_upload: {
          upload_url: presigned_put_url(bucket, key, content_type),
          bucket: bucket,
          key: key,
          expires_at: EXPIRY.from_now
        },
        errors: []
      }
    rescue ArgumentError => e
      { source_upload: nil, errors: [{ field: 'name', message: e.message, code: 422 }] }
    end

    # The payloads bucket is private and separate from the images bucket; an
    # environment without one cannot accept payloads, and says so.
    def self.payloads_bucket
      ENV.fetch('SOURCE_PAYLOADS_S3_BUCKET', '').presence
    end

    def self.images_bucket
      ENV.fetch('IMAGES_S3_BUCKET', 'images-us-east-1.echocommunity.org')
    end

    private

    def load_data_source!(source_system_key)
      DataSource.find_by(source_system_key: source_system_key) or
        raise GraphQL::ExecutionError.new("Not Found: no data source with key #{source_system_key.inspect}.", extensions: { 'code' => 404 })
    end

    def destination(data_source, kind, name)
      prefix = data_source.source_system_key
      case kind
      when 'payload'
        bucket = self.class.payloads_bucket or
          raise GraphQL::ExecutionError.new('Payload uploads are not configured on this environment (SOURCE_PAYLOADS_S3_BUCKET).', extensions: { 'code' => 503 })
        raise ArgumentError, 'payload name must be a relative path of safe characters' unless PAYLOAD_NAME.match?(name) && name.split('/').none?('..')

        [bucket, "#{prefix}/payloads/#{name}"]
      else
        raise ArgumentError, 'image name must be <ROWID>.<jpg|jpeg|png|gif|webp>' unless IMAGE_NAME.match?(name)

        [self.class.images_bucket, "#{prefix}/#{kind}s/#{name}"]
      end
    end

    def presigned_put_url(bucket, key, content_type)
      Aws::S3::Presigner.new.presigned_url(:put_object, bucket: bucket, key: key, content_type: content_type, expires_in: EXPIRY.to_i)
    end
  end
end
