# frozen_string_literal: true

module Mutations
  # Returns a presigned S3 GET URL for one of a data source's outcome files,
  # so the connector can read back what an applied run did without holding
  # AWS credentials (fpi-connector backlog A39; the mirror of
  # createSourceUpload). The sync task publishes outcomes.jsonl and
  # summary.json under <source>/outcomes/<run_id>/ in the private payloads
  # bucket after every applied run.
  #
  # Who: system superusers, and holders of the deliver_source_data capability
  # in the organization that owns the data source (decision 51): whoever may
  # deliver a run may read its outcome.
  class CreateSourceDownload < BaseMutation
    OUTCOME_NAME = %r{\A[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\z}
    EXPIRY = 15.minutes

    argument :source_system_key, String, required: true,
                                         description: 'The data source whose file is wanted, e.g. "fpi".'
    argument :kind, Types::SourceDownloadKindEnum, required: true
    argument :name, String, required: true,
                            description: '"<run_id>/<file>", e.g. "3c8a…-20260909T190918Z/summary.json".'

    field :source_download, Types::SourceDownloadType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(source_system_key:, **_attributes)
      data_source = load_data_source!(source_system_key)
      user = context[:current_user]
      allowed = user&.system_superuser? ||
                user&.organization_capability?(data_source.organization_id, :deliver_source_data)
      return true if allowed

      raise Pundit::NotAuthorizedError.new(query: :deliver_source_data, record: data_source, policy: nil)
    end

    def resolve(source_system_key:, kind:, name:)
      data_source = load_data_source!(source_system_key)
      bucket, key = location(data_source, kind, name)
      {
        source_download: {
          download_url: presigned_get_url(bucket, key),
          bucket: bucket,
          key: key,
          bytes: object_size!(bucket, key),
          expires_at: EXPIRY.from_now
        },
        errors: []
      }
    rescue ArgumentError => e
      { source_download: nil, errors: [{ field: 'name', message: e.message, code: 422 }] }
    end

    private

    def load_data_source!(source_system_key)
      DataSource.find_by(source_system_key: source_system_key) or
        raise GraphQL::ExecutionError.new("Not Found: no data source with key #{source_system_key.inspect}.", extensions: { 'code' => 404 })
    end

    def location(data_source, kind, name)
      bucket = Mutations::CreateSourceUpload.payloads_bucket or
        raise GraphQL::ExecutionError.new('Payload downloads are not configured on this environment (SOURCE_PAYLOADS_S3_BUCKET).', extensions: { 'code' => 503 })
      raise ArgumentError, 'outcome name must be <run_id>/<file> of safe characters' unless OUTCOME_NAME.match?(name) && name.split('/').none?('..')

      [bucket, "#{data_source.source_system_key}/#{kind}s/#{name}"]
    end

    # The presigned URL says nothing about whether the object exists; the
    # connector deserves a 404 now rather than an XML error from S3 later.
    def object_size!(bucket, key)
      Aws::S3::Client.new.head_object(bucket: bucket, key: key).content_length
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      raise GraphQL::ExecutionError.new("Not Found: no object at s3://#{bucket}/#{key}.", extensions: { 'code' => 404 })
    end

    def presigned_get_url(bucket, key)
      Aws::S3::Presigner.new.presigned_url(:get_object, bucket: bucket, key: key, expires_in: EXPIRY.to_i)
    end
  end
end
