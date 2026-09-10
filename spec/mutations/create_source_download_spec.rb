# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_data_source')

RSpec.describe 'Create Source Download Mutation', type: :graphql_mutation do
  let(:org) { create(:organization, :real) }
  let!(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:presigner) { instance_double(Aws::S3::Presigner, presigned_url: 'https://s3.example/get?X-Amz-Signature=abc') }
  let(:head) { instance_double(Aws::S3::Types::HeadObjectOutput, content_length: 4321) }
  let(:s3) { instance_double(Aws::S3::Client, head_object: head) }
  let(:query_string) do
    <<-GRAPHQL
      mutation($input: CreateSourceDownloadInput!) {
        createSourceDownload(input: $input) {
          errors { field message code }
          sourceDownload { downloadUrl bucket key bytes expiresAt }
        }
      }
    GRAPHQL
  end

  before do
    allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)
    allow(Aws::S3::Client).to receive(:new).and_return(s3)
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
                                         variables: { input: { sourceSystemKey: 'fpi', kind: 'OUTCOME', name: 'run-1/summary.json' }.merge(input) })
  end

  it 'refuses anonymous callers with 401' do
    result = execute(nil)
    expect(result['data']).to be_nil
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
  end

  it 'refuses a member of the source organization with 403' do
    expect(execute(org_user(role: 'member')).dig('errors', 0, 'extensions', 'code')).to eq 403
  end

  it 'gives a steward of the source organization a presigned GET on the outcomes prefix, with the size' do
    result = execute(org_user(role: 'steward'))
    expect(result['errors']).to be_nil
    download = result.dig('data', 'createSourceDownload', 'sourceDownload')
    expect(download).to include('bucket' => 'plant-api-staging-source-payloads', 'key' => 'fpi/outcomes/run-1/summary.json', 'bytes' => 4321)
    expect(download['downloadUrl']).to start_with('https://s3.example/get')
    expect(Time.zone.parse(download['expiresAt'])).to be_within(1.minute).of(15.minutes.from_now)
    expect(presigner).to have_received(:presigned_url).with(:get_object, bucket: 'plant-api-staging-source-payloads',
                                                                         key: 'fpi/outcomes/run-1/summary.json', expires_in: 900)
    expect(s3).to have_received(:head_object).with(bucket: 'plant-api-staging-source-payloads', key: 'fpi/outcomes/run-1/summary.json')
  end

  it 'lets a system superuser read without an organization role' do
    expect(execute(build(:user, :superadmin)).dig('data', 'createSourceDownload', 'sourceDownload', 'key')).to eq('fpi/outcomes/run-1/summary.json')
  end

  it 'returns 404 when the outcome file does not exist' do
    allow(s3).to receive(:head_object).and_raise(Aws::S3::Errors::NotFound.new(nil, 'not found'))
    result = execute(org_user(role: 'steward'))
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq 404
    expect(result.dig('errors', 0, 'message')).to match(%r{fpi/outcomes/run-1/summary.json})
  end

  it 'refuses unsafe or shapeless names' do
    result = execute(org_user(role: 'steward'), name: '../payloads/run-1/shard-000.json')
    expect(result.dig('data', 'createSourceDownload', 'errors', 0)).to include('field' => 'name', 'code' => 422)
    result = execute(org_user(role: 'steward'), name: 'summary.json')
    expect(result.dig('data', 'createSourceDownload', 'errors', 0, 'message')).to match(%r{<run_id>/<file>})
  end

  it 'says so when the environment has no payloads bucket' do
    allow(Mutations::CreateSourceUpload).to receive(:payloads_bucket).and_return(nil)
    result = execute(org_user(role: 'steward'))
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq 503
  end

  it 'returns 404 for an unknown data source' do
    expect(execute(build(:user, :superadmin), sourceSystemKey: 'nope').dig('errors', 0, 'extensions', 'code')).to eq 404
  end
end
