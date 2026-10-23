# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/staging_org_repoint')

# Option B (2026-10-23): staging must use the ECHOcommunity staging
# organization ids, exactly as production uses one id per organization in both
# systems. This tool rewrites ownership on a whole environment, so the specs
# pin the things that must hold before anyone runs it: every reference moves,
# a dry run writes nothing, production is refused, the reverse mapping restores
# the original state, and a second run is a no-op.
RSpec.describe StagingOrgRepoint do
  let(:placeholder_id) { 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeffff0001' }
  let(:target_id)      { '149f6971-b63a-45e7-be7f-e67fc7d7b3d6' }
  let(:mapping)        { { placeholder_id => target_id } }

  let!(:placeholder) { Organization.mirror_real!(external_id: placeholder_id, name: 'ECHO (staging rehearsal)') }
  let(:connection)   { ActiveRecord::Base.connection }

  # One record of every organization-owned kind, plus the data source, all
  # owned by and sourced from the given organization.
  def owned_world(org_id)
    owned = { owner_organization_id: org_id, source_organization_id: org_id }
    plant = create(:plant, **owned)
    variety = create(:variety, plant: plant, **owned)
    location = create(:location, **owned)
    {
      plant: plant,
      variety: variety,
      specimen: create(:specimen, plant: plant, variety: variety, **owned),
      location: location,
      category: create(:category, **owned),
      data_source: create(:data_source, organization_id: org_id)
    }
  end

  def references_to(org_id)
    described_class.references(connection).sum do |table, column|
      connection.select_value(
        "SELECT count(*) FROM #{connection.quote_table_name(table)} " \
        "WHERE #{connection.quote_column_name(column)} = #{connection.quote(org_id)}"
      ).to_i
    end
  end

  def run(map = mapping, apply: true)
    described_class.new(mapping: map, apply: apply, out: StringIO.new).run
  end

  describe '.references' do
    # The tool discovers referencing columns from the database catalog, so a
    # new foreign key to organizations is moved without a code change. This
    # list exists so that such a change is at least noticed in review.
    it 'finds every foreign key that points at organizations.id' do
      expect(described_class.references(connection)).to match_array(
        [%w[categories owner_organization_id], %w[categories source_organization_id],
         %w[data_sources organization_id],
         %w[locations owner_organization_id], %w[locations source_organization_id],
         %w[plants owner_organization_id], %w[plants source_organization_id],
         %w[specimens owner_organization_id], %w[specimens source_organization_id],
         %w[varieties owner_organization_id], %w[varieties source_organization_id]]
      )
    end
  end

  describe 'applying' do
    let!(:world) { owned_world(placeholder_id) }

    it 'moves every referencing row to the target organization' do
      run
      world.each_value(&:reload)
      %i[plant variety specimen location category].each do |kind|
        expect(world[kind].owner_organization_id).to eq(target_id), kind.to_s
        expect(world[kind].source_organization_id).to eq(target_id), kind.to_s
      end
      expect(world[:data_source].organization_id).to eq(target_id)
      expect(references_to(placeholder_id)).to eq(0)
    end

    it 'creates the target as a mirrored real organization whose id is the IdP id' do
      run
      target = Organization.find(target_id)
      expect(target).to have_attributes(kind: 'real', external_idp_id: target_id, name: 'ECHO (staging rehearsal)')
    end

    it 'retires the placeholder organization row' do
      run
      expect(Organization.exists?(placeholder_id)).to be(false)
    end

    it 'adopts an existing target row (already mirrored from a login) instead of creating one' do
      existing = Organization.mirror_real!(external_id: target_id, name: 'ECHO')
      already = create(:plant, owner_organization_id: target_id, source_organization_id: target_id)

      result = run.first

      expect(result.target_created).to be(false)
      expect(result.target_rows_before).to eq(2) # the plant's owner and source columns
      expect(existing.reload.name).to eq('ECHO')
      expect(already.reload.owner_organization_id).to eq(target_id)
      expect(references_to(target_id)).to eq(13)
    end

    it 'reports the count moved for every referencing column' do
      create(:plant, owner_organization_id: placeholder_id, source_organization_id: placeholder_id)
      result = run.first

      expect(result.status).to eq(:repointed)
      expect(result.moved).to include('plants.owner_organization_id' => 2, 'plants.source_organization_id' => 2,
                                      'varieties.owner_organization_id' => 1, 'data_sources.organization_id' => 1)
      expect(result.moved.values.sum).to eq(13)
    end

    it 'leaves untouched the rows of other organizations' do
      other = owned_world(Organization.mirror_real!(external_id: SecureRandom.uuid, name: 'Other').id)
      run
      expect(other[:plant].reload.owner_organization_id).to eq(other[:data_source].organization_id)
    end

    it 'does not touch updated_at (an ownership move is not a content change)' do
      before = world[:plant].reload.updated_at
      run
      expect(world[:plant].reload.updated_at).to eq(before)
    end

    it 'prints counts and ids only' do
      out = StringIO.new
      described_class.new(mapping: mapping, apply: true, out: out).run
      expect(out.string).to include(placeholder_id, target_id, 'plants.owner_organization_id: 1')
      expect(out.string).not_to include('ECHO (staging rehearsal)', world[:plant].owned_by)
    end

    it 'is a no-op when run a second time' do
      run
      snapshot = references_to(target_id)
      second = run.first

      expect(second.status).to eq(:already_repointed)
      expect(second.moved.values.sum).to eq(0)
      expect(references_to(target_id)).to eq(snapshot)
      expect(Organization.where(id: [placeholder_id, target_id]).pluck(:id)).to eq([target_id])
    end

    it 'restores the original ids when the mapping is reversed' do
      run
      run(described_class.invert(mapping))

      world.each_value(&:reload)
      expect(world[:plant].owner_organization_id).to eq(placeholder_id)
      expect(world[:category].source_organization_id).to eq(placeholder_id)
      expect(world[:data_source].organization_id).to eq(placeholder_id)
      expect(Organization.find(placeholder_id)).to have_attributes(kind: 'real', external_idp_id: placeholder_id)
      expect(Organization.exists?(target_id)).to be(false)
      expect(references_to(placeholder_id)).to eq(11)
    end

    it 'rolls the organization back whole when a step fails' do
      repoint = described_class.new(mapping: mapping, apply: true, out: StringIO.new)
      allow(repoint).to receive(:retire!).and_raise(ActiveRecord::ActiveRecordError, 'boom')

      expect { repoint.run }.to raise_error(ActiveRecord::ActiveRecordError, 'boom')
      expect(world[:plant].reload.owner_organization_id).to eq(placeholder_id)
      expect(world[:data_source].reload.organization_id).to eq(placeholder_id)
      expect(Organization.exists?(target_id)).to be(false)
    end
  end

  describe 'dry run' do
    let!(:world) { owned_world(placeholder_id) }

    it 'writes nothing' do
      versions = PaperTrail::Version.count
      result = run(apply: false).first

      expect(result.status).to eq(:would_repoint)
      expect(result.moved.values.sum).to eq(11)
      expect(world[:plant].reload.owner_organization_id).to eq(placeholder_id)
      expect(Organization.exists?(placeholder_id)).to be(true)
      expect(Organization.exists?(target_id)).to be(false)
      expect(PaperTrail::Version.count).to eq(versions)
    end

    it 'says so' do
      out = StringIO.new
      described_class.new(mapping: mapping, apply: false, out: out).run
      expect(out.string).to include('DRY RUN', 'would move')
    end
  end

  describe 'refusals' do
    it 'refuses a mapping whose source is a personal organization' do
      personal = create(:organization, :personal)
      expect { run({ personal.id => target_id }) }.to raise_error(described_class::Refused, /personal/)
    end

    it 'refuses when neither organization exists' do
      expect { run({ SecureRandom.uuid => SecureRandom.uuid }) }.to raise_error(described_class::Refused, /neither/)
    end

    it 'refuses when another row already claims the target IdP id under a different local id' do
      Organization.create!(id: SecureRandom.uuid, kind: 'real', external_idp_id: target_id, name: 'Pre-adoption')
      expect { run }.to raise_error(described_class::Refused, /external_idp_id/)
      expect(Organization.exists?(placeholder_id)).to be(true)
    end
  end

  describe '.parse_mapping' do
    it 'parses comma-separated from:to pairs and lower-cases them' do
      expect(described_class.parse_mapping("#{placeholder_id.upcase}:#{target_id}"))
        .to eq(placeholder_id => target_id)
    end

    it 'refuses malformed ids' do
      expect { described_class.parse_mapping('nope:also-nope') }.to raise_error(described_class::Refused, /malformed/)
    end

    it 'refuses a pair that maps an id to itself' do
      expect { described_class.parse_mapping("#{target_id}:#{target_id}") }
        .to raise_error(described_class::Refused, /itself/)
    end

    it 'refuses chains (an id that is both a source and a target)' do
      third = SecureRandom.uuid
      expect { described_class.parse_mapping("#{placeholder_id}:#{target_id},#{target_id}:#{third}") }
        .to raise_error(described_class::Refused, /both/)
    end

    it 'refuses two sources mapped onto one target' do
      expect { described_class.parse_mapping("#{placeholder_id}:#{target_id},#{SecureRandom.uuid}:#{target_id}") }
        .to raise_error(described_class::Refused, /more than once/)
    end
  end

  describe '.mapping_from_env' do
    it 'defaults to the built-in staging mapping' do
      expect(described_class.mapping_from_env({})).to eq(described_class::STAGING_MAPPING)
    end

    it 'maps the staging placeholders onto the ECHOcommunity staging organizations' do
      expect(described_class::STAGING_MAPPING).to eq(
        'aaaaaaaa-bbbb-4ccc-8ddd-eeeeffff0001' => '149f6971-b63a-45e7-be7f-e67fc7d7b3d6',
        'b7ab3117-e610-4b7d-b097-a51ebe911d79' => 'ad8f2875-2bd5-46fb-b514-9f6becf47ad4'
      )
    end

    it 'accepts FROM and TO for a single pair' do
      expect(described_class.mapping_from_env('FROM' => placeholder_id, 'TO' => target_id))
        .to eq(placeholder_id => target_id)
    end

    it 'requires FROM and TO together' do
      expect { described_class.mapping_from_env('FROM' => placeholder_id) }
        .to raise_error(described_class::Refused, /FROM and TO/)
    end

    it 'accepts MAPPING' do
      expect(described_class.mapping_from_env('MAPPING' => "#{placeholder_id}:#{target_id}"))
        .to eq(placeholder_id => target_id)
    end

    it 'inverts the mapping with REVERSE=true' do
      expect(described_class.mapping_from_env('REVERSE' => 'true'))
        .to eq(described_class::STAGING_MAPPING.invert)
    end
  end

  describe '.guard!' do
    before { allow(connection).to receive(:current_database).and_return('Plant_API_staging') }

    it 'allows a dry run on the staging database' do
      expect { described_class.guard!(apply: false, confirm: nil, env: 'staging') }.not_to raise_error
    end

    it 'allows an apply on staging with the confirmation value' do
      expect { described_class.guard!(apply: true, confirm: 'REPOINT-STAGING-ORGS', env: 'staging') }
        .not_to raise_error
    end

    it 'refuses an apply without the confirmation value' do
      expect { described_class.guard!(apply: true, confirm: 'yes', env: 'staging') }
        .to raise_error(described_class::Refused, /CONFIRM=REPOINT-STAGING-ORGS/)
    end

    it 'refuses RAILS_ENV=production even with the confirmation value, dry run included' do
      [true, false].each do |apply|
        expect { described_class.guard!(apply: apply, confirm: 'REPOINT-STAGING-ORGS', env: 'production') }
          .to raise_error(described_class::Refused, /production/)
      end
    end

    it 'refuses any database other than the staging one' do
      allow(connection).to receive(:current_database).and_return('Plant_API_production')
      expect { described_class.guard!(apply: false, confirm: nil, env: 'staging') }
        .to raise_error(described_class::Refused, /Plant_API_production/)
    end
  end
end
