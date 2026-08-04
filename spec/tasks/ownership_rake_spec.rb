# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Load the top-level with_mapping_path helper defined in ownership.rake.
# We load it via the task namespace (rails loads all lib/tasks/**/*.rake
# when the :environment task prerequisite runs), but for unit isolation
# we load it explicitly here.
Rails.application.load_tasks if Rake::Task.tasks.empty?

RSpec.describe 'with_mapping_path (ownership.rake helper)' do
  # Build a minimal valid mapping JSON body.
  def valid_mapping_json
    echo_id = SecureRandom.uuid
    {
      'generated_at' => Time.current.iso8601,
      'users' => [{ 'uid' => SecureRandom.uuid, 'email' => 'a@example.com', 'name' => 'A' }],
      'organizations' => [{ 'id' => echo_id, 'name' => 'ECHO', 'slug' => 'echo' }]
    }.to_json
  end

  context 'when MAPPING is a local filesystem path' do
    it 'yields the path unchanged and does not call Aws::S3::Client' do
      allow(Aws::S3::Client).to receive(:new)

      Tempfile.create(['mapping', '.json']) do |f|
        f.write(valid_mapping_json)
        f.flush
        yielded = nil
        with_mapping_path(f.path) { |p| yielded = p }
        expect(yielded).to eq(f.path)
      end

      expect(Aws::S3::Client).not_to have_received(:new)
    end
  end

  context 'when MAPPING is an s3:// URI' do
    let(:s3_uri) { 's3://my-images-bucket/ownership-backfill/mapping.json' }
    let(:fake_s3) { instance_double(Aws::S3::Client) }
    let(:json_body) { valid_mapping_json }

    before do
      allow(Aws::S3::Client).to receive(:new).and_return(fake_s3)
      allow(fake_s3).to receive(:get_object) do |args|
        # Simulate writing the JSON to the response_target path.
        File.write(args[:response_target], json_body)
      end
    end

    it 'calls get_object with the correct bucket and key' do
      with_mapping_path(s3_uri) { |_p| nil }

      expect(fake_s3).to have_received(:get_object).with(
        hash_including(bucket: 'my-images-bucket', key: 'ownership-backfill/mapping.json')
      )
    end

    it 'yields a local path whose content matches the downloaded JSON' do
      yielded_content = nil
      with_mapping_path(s3_uri) { |p| yielded_content = File.read(p) }
      expect(yielded_content).to eq(json_body)
    end

    it 'deletes the tempfile after the block returns' do
      captured_path = nil
      with_mapping_path(s3_uri) { |p| captured_path = p }
      expect(File).not_to exist(captured_path)
    end

    it 'deletes the tempfile even when the block raises' do
      captured_path = nil
      begin
        with_mapping_path(s3_uri) do |p|
          captured_path = p
          raise 'intentional error'
        end
      rescue RuntimeError
        nil
      end
      expect(File).not_to exist(captured_path)
    end

    it 'handles keys with multiple path segments' do
      uri = 's3://bucket/deep/nested/path/mapping.json'
      allow(Aws::S3::Client).to receive(:new).and_return(fake_s3)
      allow(fake_s3).to receive(:get_object) { |args| File.write(args[:response_target], '{}') }

      with_mapping_path(uri) { |_p| nil }

      expect(fake_s3).to have_received(:get_object).with(
        hash_including(bucket: 'bucket', key: 'deep/nested/path/mapping.json')
      )
    end
  end
end
