# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_data_source')

RSpec.describe 'Create Source Upload Mutation', type: :graphql_mutation do
  let(:org) { create(:organization, :real) }
  let!(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:presigner) { instance_double(Aws::S3::Presigner, presigned_url: 'https://s3.example/put?X-Amz-Signature=abc') }
  let(:query_string) do
    <<-GRAPHQL
      mutation($input: CreateSourceUploadInput!) {
        createSourceUpload(input: $input) {
          errors { field message code }
          sourceUpload { uploadUrl bucket key expiresAt }
        }
      }
    GRAPHQL
  end

  before do
    allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)
    allow(Mutations::CreateSourceUpload).to receive(:payloads_bucket).and_return('plant-api-staging-source-payloads')
  end

  def org_user(role:, trust: 4)
    principal = create(:principal)
    User.new('uid' => principal.external_uid, 'email' => principal.email, 'trust_levels' => { 'plant' => trust },
             'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => role } }]).tap do |u|
      u.principal = principal
      u.personal_organization = Organization.personal_for!(principal)
    end
  end

  def execute(user, **input)
    PlantApiSchema.execute(query_string, context: { current_user: user },
                                         variables: { input: { sourceSystemKey: 'fpi', kind: 'PAYLOAD', name: 'run-1/shard-000.json', contentType: 'application/json' }.merge(input) })
  end

  it 'refuses anonymous callers with 401' do
    result = execute(nil)
    expect(result['data']).to be_nil
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
  end

  it 'refuses a member of the source organization with 403' do
    result = execute(org_user(role: 'member'))
    expect(result['data']).to be_nil
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
  end

  it 'refuses a steward of another organization' do
    other = create(:organization, :real)
    principal = create(:principal)
    stranger = User.new('uid' => principal.external_uid, 'email' => principal.email, 'trust_levels' => { 'plant' => 4 },
                        'organizations' => [{ 'id' => other.id, 'name' => other.name, 'roles' => { 'plant' => 'steward' } }])
    stranger.principal = principal
    stranger.personal_organization = Organization.personal_for!(principal)
    expect(execute(stranger).dig('errors', 0, 'extensions', 'code')).to eq 403
  end

  it 'gives a steward of the source organization a presigned PUT for a payload under the private prefix' do
    result = execute(org_user(role: 'steward'))
    expect(result['errors']).to be_nil
    upload = result.dig('data', 'createSourceUpload', 'sourceUpload')
    expect(upload).to include('bucket' => 'plant-api-staging-source-payloads', 'key' => 'fpi/payloads/run-1/shard-000.json')
    expect(upload['uploadUrl']).to start_with('https://s3.example/put')
    expect(Time.zone.parse(upload['expiresAt'])).to be_within(1.minute).of(15.minutes.from_now)
    expect(presigner).to have_received(:presigned_url).with(:put_object, bucket: 'plant-api-staging-source-payloads',
                                                                         key: 'fpi/payloads/run-1/shard-000.json',
                                                                         content_type: 'application/json', expires_in: 900)
  end

  it 'lets a system superuser deliver without an organization role' do
    result = execute(build(:user, :superadmin))
    expect(result.dig('data', 'createSourceUpload', 'sourceUpload', 'key')).to eq('fpi/payloads/run-1/shard-000.json')
  end

  it 'puts images under the images bucket keyed by kind and source row' do
    result = execute(org_user(role: 'steward'), kind: 'DRAWING', name: '6.jpg', contentType: 'image/jpeg')
    expect(result.dig('data', 'createSourceUpload', 'sourceUpload')).to include('bucket' => Mutations::CreateSourceUpload.images_bucket, 'key' => 'fpi/drawings/6.jpg')
  end

  it 'refuses unsafe names in the payload' do
    result = execute(org_user(role: 'steward'), name: '../other/shard.json')
    expect(result.dig('data', 'createSourceUpload', 'sourceUpload')).to be_nil
    expect(result.dig('data', 'createSourceUpload', 'errors', 0)).to include('field' => 'name', 'code' => 422)
    result = execute(org_user(role: 'steward'), kind: 'PHOTO', name: 'not-a-rowid.jpg', contentType: 'image/jpeg')
    expect(result.dig('data', 'createSourceUpload', 'errors', 0, 'message')).to match(/ROWID/)
  end

  it 'says so when the environment has no payloads bucket' do
    allow(Mutations::CreateSourceUpload).to receive(:payloads_bucket).and_return(nil)
    result = execute(org_user(role: 'steward'))
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq 503
    expect(result.dig('errors', 0, 'message')).to match(/SOURCE_PAYLOADS_S3_BUCKET/)
  end

  it 'returns 404 for an unknown data source' do
    result = execute(build(:user, :superadmin), sourceSystemKey: 'nope')
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq 404
  end
end
