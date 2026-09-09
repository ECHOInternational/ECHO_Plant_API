# frozen_string_literal: true

require 'aws-sdk-s3'
require 'tmpdir'

# Where an FPI payload lives and where its outcomes go (fpi-connector
# decision 43).
#
# The connector delivers a run to the private payloads bucket under
# fpi/payloads/<run_id>/ through createSourceUpload. The sync task runs as a
# one-off Fargate task with no shared disk, so the fpi rake tasks accept a
# payload argument that is either a local directory or s3://bucket/prefix;
# this class fetches the latter into a temporary directory the run can read
# like any other. After an applied run the outcome files are published next
# to the payload, under fpi/outcomes/<run_id>/, so they outlive the task.
class FpiPayloadStore
  class NotFound < StandardError; end

  S3_URI = %r{\As3://(?<bucket>[^/\s]+)/(?<prefix>\S+?)/?\z}
  MANIFEST = 'payload-manifest.json'
  CONTENT_TYPES = { '.json' => 'application/json', '.jsonl' => 'application/x-ndjson' }.freeze

  attr_reader :bucket, :prefix

  def self.s3?(path)
    path.to_s.start_with?('s3://')
  end

  # [directory to read, files fetched]; a local path passes through untouched.
  def self.materialize(path, client: nil)
    return [Pathname(path), []] unless s3?(path)

    new(path, client: client).download
  end

  # Copies the run's outcome files beside an S3 payload, under
  # <root>/outcomes/<run_id>/; nil for a local payload. The run id names the
  # target, not the payload prefix: a second pass over the same payload keeps
  # its own outcomes.
  def self.publish_outcomes(payload_path, out_dir, run_id:, client: nil)
    return nil unless s3?(payload_path)

    new(payload_path, client: client).upload_outcomes(Pathname(out_dir), run_id)
  end

  def initialize(uri, client: nil)
    match = S3_URI.match(uri.to_s) or raise ArgumentError, "not an s3://bucket/prefix URI: #{uri}"
    @bucket = match[:bucket]
    @prefix = match[:prefix]
    @client = client || Aws::S3::Client.new
  end

  def download
    keys = run_file_keys
    raise NotFound, "no #{MANIFEST} under s3://#{bucket}/#{prefix}/" unless keys.include?("#{prefix}/#{MANIFEST}")

    dir = Pathname(Dir.mktmpdir('fpi-payload'))
    keys.each { |key| @client.get_object(bucket: bucket, key: key, response_target: dir.join(File.basename(key)).to_s) }
    [dir, keys.map { |key| File.basename(key) }]
  end

  # fpi/payloads/<anything> -> fpi/outcomes/<run_id>; a prefix without a
  # payloads segment gets outcomes/<run_id> appended.
  def outcomes_prefix(run_id)
    match = prefix.match(%r{\A(?<root>(?:.*?/)?)payloads/})
    match ? "#{match[:root]}outcomes/#{run_id}" : "#{prefix}/outcomes/#{run_id}"
  end

  def upload_outcomes(out_dir, run_id)
    target = outcomes_prefix(run_id)
    out_dir.children.select(&:file?).sort.each do |file|
      @client.put_object(bucket: bucket, key: "#{target}/#{file.basename}", body: file.read,
                         content_type: CONTENT_TYPES.fetch(file.extname, 'application/octet-stream'))
    end
    "s3://#{bucket}/#{target}/"
  end

  private

  # Only the run's own files: nothing nested, no folder markers.
  def run_file_keys
    keys = []
    @client.list_objects_v2(bucket: bucket, prefix: "#{prefix}/").each_page { |page| keys.concat(page.contents.map(&:key)) }
    keys.select { |key| File.dirname(key) == prefix && !key.end_with?('/') }
  end
end
