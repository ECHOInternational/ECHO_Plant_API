# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SandboxOrganizations do
  describe '.parse' do
    it 'returns no claims when unset or blank' do
      expect(described_class.parse(nil)).to eq []
      expect(described_class.parse('')).to eq []
      expect(described_class.parse('   ')).to eq []
    end

    it 'builds a JWT-shaped claim per entry' do
      claims = described_class.parse('ECHO Asia:editor')
      expect(claims.size).to eq 1
      expect(claims.first).to include(
        'name' => 'ECHO Asia',
        'roles' => { 'plant' => 'editor' }
      )
      expect(claims.first['id']).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'defaults the role to org_admin' do
      expect(described_class.parse('ECHO Asia').first['roles']).to eq('plant' => 'org_admin')
    end

    it 'parses several comma separated entries and trims whitespace' do
      claims = described_class.parse(' ECHO Asia : editor , ECHO North America:steward ')
      expect(claims.map { |c| c['name'] }).to eq ['ECHO Asia', 'ECHO North America']
      expect(claims.map { |c| c['roles']['plant'] }).to eq %w[editor steward]
    end

    it 'skips entries naming an unknown role rather than granting nothing silently' do
      allow(Rails.logger).to receive(:warn)
      claims = described_class.parse('Good Org:editor,Typo Org:editr')
      expect(claims.map { |c| c['name'] }).to eq ['Good Org']
      expect(Rails.logger).to have_received(:warn).with(/Typo Org.*editr/)
    end

    it 'skips empty entries' do
      expect(described_class.parse('ECHO Asia,,  ,:editor').map { |c| c['name'] }).to eq ['ECHO Asia']
    end

    # docker compose env_file keeps quotes as part of the value, unlike dotenv.
    it 'tolerates a value wrapped in quotes' do
      %w[' "].each do |quote|
        claims = described_class.parse("#{quote}ECHO Asia:editor,ECHO North America#{quote}")
        expect(claims.map { |c| c['name'] }).to eq ['ECHO Asia', 'ECHO North America']
      end
    end

    it 'leaves an unmatched quote alone rather than guessing' do
      expect(described_class.parse("'ECHO Asia").first['name']).to eq "'ECHO Asia"
    end
  end

  describe '.id_for' do
    it 'derives a stable uuid from the name' do
      expect(described_class.id_for('ECHO Asia')).to eq described_class.id_for('ECHO Asia')
    end

    it 'derives different ids for different names' do
      expect(described_class.id_for('ECHO Asia')).not_to eq described_class.id_for('ECHO North America')
    end

    # The mirror upsert adopts the claim id as the local primary key, so a
    # non-uuid would fail the insert and degrade the whole request to legacy
    # authorization.
    it 'produces a value the organizations primary key accepts' do
      id = described_class.id_for('ECHO Asia')
      org = Organization.mirror_real!(external_id: id, name: 'ECHO Asia')
      expect(org.id).to eq id
      expect(org.kind).to eq 'real'
    end
  end
end
