# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Create Upload Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:canned_url) { 'https://images-us-east-1.echocommunity.org/uploads/some-uuid/photo.jpg?X-Amz-Signature=abc' }
  let(:presigner_double) do
    instance_double(Aws::S3::Presigner,
                    presigned_url: canned_url)
  end

  let(:query_string) do
    <<-GRAPHQL
      mutation($input: CreateUploadInput!) {
        createUpload(input: $input) {
          errors {
            field
            message
            code
          }
          upload {
            imageId
            uploadUrl
            bucket
            key
          }
        }
      }
    GRAPHQL
  end

  before do
    allow(Aws::S3::Presigner).to receive(:new).and_return(presigner_double)
  end

  context 'when user is not authenticated' do
    let(:current_user) { nil }

    it 'returns a 401 error' do
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: { input: { filename: 'photo.jpg', contentType: 'image/jpeg' } }
      )
      expect(result['data']).to be_nil
      expect(result['errors']).not_to be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 401
    end
  end

  context 'when user is read-only' do
    let(:current_user) { build(:user, :readonly) }

    it 'returns a 403 error' do
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: { input: { filename: 'photo.jpg', contentType: 'image/jpeg' } }
      )
      expect(result['data']).to be_nil
      expect(result['errors']).not_to be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 403
    end
  end

  context 'when user has write access' do
    let(:current_user) { build(:user, :readwrite) }

    before do
      @result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: { input: { filename: 'photo.jpg', contentType: 'image/jpeg' } }
      )
    end

    it 'completes successfully without top-level errors' do
      expect(@result['errors']).to be_nil
      expect(@result['data']).not_to be_nil
    end

    it 'returns an imageId that is a UUID' do
      upload = @result['data']['createUpload']['upload']
      expect(upload['imageId']).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'returns an uploadUrl' do
      upload = @result['data']['createUpload']['upload']
      expect(upload['uploadUrl']).to eq canned_url
    end

    it 'returns a bucket' do
      upload = @result['data']['createUpload']['upload']
      expect(upload['bucket']).not_to be_blank
    end

    it 'returns a key prefixed with uploads/<uuid>/' do
      upload = @result['data']['createUpload']['upload']
      expect(upload['key']).to match(%r{\Auploads/[0-9a-f-]{36}/})
    end

    it 'returns no payload errors' do
      errors = @result['data']['createUpload']['errors']
      expect(errors).to be_empty
    end
  end

  context 'filename sanitization' do
    let(:current_user) { build(:user, :readwrite) }

    it 'strips path components and keeps extension safe' do
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: { input: { filename: '../evil/../a b.jpg', contentType: 'image/jpeg' } }
      )
      upload = result['data']['createUpload']['upload']
      # The key is uploads/<uuid>/<safe-basename>. The basename must contain no path traversal.
      basename = upload['key'].split('/').last
      expect(basename).not_to include('..')
      expect(basename).not_to include('/')
    end

    it 'sanitized filename preserves the extension' do
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: { input: { filename: '../evil/../a b.jpg', contentType: 'image/jpeg' } }
      )
      upload = result['data']['createUpload']['upload']
      # key is uploads/<uuid>/<safe-name>. The basename after the uuid should end with .jpg.
      basename = upload['key'].split('/').last
      expect(basename).to end_with('.jpg')
    end
  end

  context 'presigner arguments' do
    let(:current_user) { build(:user, :readwrite) }
    let(:expected_bucket) { ENV.fetch('IMAGES_S3_BUCKET', 'images-us-east-1.echocommunity.org') }

    it 'calls the presigner with the correct bucket and key' do
      expected_key = nil

      allow(presigner_double).to receive(:presigned_url) do |_method, bucket:, key:, **_opts|
        expected_key = key
        expect(bucket).to eq expected_bucket
        expect(key).to match(%r{\Auploads/[0-9a-f-]{36}/})
        canned_url
      end

      PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: { input: { filename: 'photo.jpg', contentType: 'image/jpeg' } }
      )
    end

    it 'passes content_type to the presigner' do
      allow(presigner_double).to receive(:presigned_url) do |_method, **opts|
        expect(opts[:content_type]).to eq 'image/jpeg'
        canned_url
      end

      PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: { input: { filename: 'photo.jpg', contentType: 'image/jpeg' } }
      )
    end

    it 'passes expires_in to the presigner' do
      allow(presigner_double).to receive(:presigned_url) do |_method, **opts|
        expect(opts[:expires_in]).to eq(900)
        canned_url
      end

      PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: { input: { filename: 'photo.jpg', contentType: 'image/jpeg' } }
      )
    end
  end

  context 'empty filename edge case' do
    let(:current_user) { build(:user, :readwrite) }

    it 'uses "upload" as default filename when filename is empty' do
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: { input: { filename: '', contentType: 'image/jpeg' } }
      )
      upload = result['data']['createUpload']['upload']
      # key is uploads/<uuid>/<safe-name>. With empty filename, basename should be 'upload'.
      expect(upload['key']).to end_with('/upload')
    end
  end
end
