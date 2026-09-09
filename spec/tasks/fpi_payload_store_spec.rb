# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_payload_store')

RSpec.describe FpiPayloadStore do
  let(:client) { Aws::S3::Client.new(stub_responses: true, region: 'us-east-1') }

  it 'passes a local directory through untouched' do
    dir, files = described_class.materialize('/tmp/some/payload', client: client)
    expect(dir).to eq(Pathname('/tmp/some/payload'))
    expect(files).to be_empty
  end

  it 'publishes nothing for a local payload' do
    expect(described_class.publish_outcomes('/tmp/payload', '/tmp/out', client: client)).to be_nil
  end

  describe 'an s3:// payload' do
    let(:uri) { 's3://payloads/fpi/payloads/run-1' }

    before do
      client.stub_responses(:list_objects_v2, {
                              contents: [{ key: 'fpi/payloads/run-1/shard-000.json' },
                                         { key: 'fpi/payloads/run-1/payload-manifest.json' },
                                         { key: 'fpi/payloads/run-1/nested/ignored.json' },
                                         { key: 'fpi/payloads/run-1/' }]
                            })
      client.stub_responses(:get_object, ->(context) { { body: "content of #{File.basename(context.params[:key])}" } })
    end

    it 'downloads the run files into a temporary directory' do
      dir, files = described_class.materialize(uri, client: client)
      expect(files).to eq(%w[shard-000.json payload-manifest.json])
      expect(dir.join('payload-manifest.json').read).to eq('content of payload-manifest.json')
      expect(dir.join('shard-000.json').read).to eq('content of shard-000.json')
    ensure
      FileUtils.rm_rf(dir) if dir
    end

    it 'refuses a prefix without a manifest' do
      client.stub_responses(:list_objects_v2, { contents: [{ key: 'fpi/payloads/run-1/shard-000.json' }] })
      expect { described_class.materialize(uri, client: client) }.to raise_error(described_class::NotFound, /payload-manifest.json/)
    end

    it 'publishes the outcome files next to the payload under outcomes/' do
      out = Pathname(Dir.mktmpdir('fpi-out'))
      out.join('summary.json').write('{}')
      out.join('outcomes.jsonl').write("{}\n")
      puts = []
      client.stub_responses(:put_object, lambda { |context|
        puts << [context.params[:key], context.params[:content_type], context.params[:body]]
        {}
      })
      expect(described_class.publish_outcomes(uri, out, client: client)).to eq('s3://payloads/fpi/outcomes/run-1/')
      expect(puts).to eq([['fpi/outcomes/run-1/outcomes.jsonl', 'application/x-ndjson', "{}\n"],
                          ['fpi/outcomes/run-1/summary.json', 'application/json', '{}']])
    ensure
      FileUtils.rm_rf(out) if out
    end

    it 'rejects anything that is not bucket/prefix' do
      expect { described_class.new('s3://bucket-only') }.to raise_error(ArgumentError, %r{bucket/prefix})
    end
  end
end
