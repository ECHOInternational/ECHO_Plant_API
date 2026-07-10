# frozen_string_literal: true

require 'rails_helper'

# Compatibility guard for the paper_trail 10.3.1 -> 12.3.0 bump on frozen Rails 6.0.
#
# Two concerns are pinned here:
#   1. PT-10-era production YAML stored in versions.object stays reify-able. This is
#      the tripwire that will catch the Psych 4 safe-load change when Ruby 3.1 lands
#      later in the ladder.
#   2. The live create/update/destroy versioning cycle on PT 12 still writes one row
#      per event, populates whodunnit, and round-trips through reify.
#
# NOTE ON item_id: every model PK is a uuid but versions.item_id is bigint, so PT
# stores uuid.to_i (== 0) for item_id. That is a known, intentionally-unfixed
# production fact (ladder step 19). These specs deliberately do not depend on or
# assert anything about item_id.
RSpec.describe 'PaperTrail 12 compatibility', type: :model do
  let(:fixture_path) do
    Rails.root.join('spec', 'fixtures', 'paper_trail', 'specimen_version_object_pt10.yml')
  end
  let(:fixture_object) { File.read(fixture_path) }

  describe 'reifying PT-10-era production YAML (tripwire)' do
    it 'reifies a Specimen whose scalars match the stored object payload' do
      version = PaperTrail::Version.new(
        item_type: 'Specimen',
        item_id: 0,
        event: 'update',
        object: fixture_object
      )

      specimen = version.reify

      expect(specimen).to be_a(Specimen)
      expect(specimen.id).to eq('de68e499-3ff6-4954-b3fa-8ec754923b74')
      expect(specimen.name).to eq('Galangal')
      # visibility is stored as the integer enum value (0) in the payload
      expect(specimen.visibility).to eq('private')
      expect(specimen.plant_id).to eq('2cdf168c-ef32-49bf-8d7d-cec2b2ba2069')
      expect(specimen.variety_id).to eq('d8a267dc-830c-4922-a666-1a77609d1bf1')
      expect(specimen.owned_by).to eq('user@example.org')
      expect(specimen.created_by).to eq('user@example.org')
    end

    it 'parses the payload through the same serializer path the app uses' do
      parsed = PaperTrail.serializer.load(fixture_object)

      expect(parsed).to be_a(Hash)
      expect(parsed['name']).to eq('Galangal')
      expect(parsed['visibility']).to eq(0)
    end
  end

  describe 'live create/update/destroy versioning cycle', versioning: true do
    # Persist the associated plant/variety first so their (also-versioned) rows are
    # not counted against the specimen's own create/update/destroy cycle.
    let(:plant) { create(:plant) }
    let(:variety) { create(:variety, plant: plant) }

    # IMPORTANT: we query PaperTrail::Version directly by item_type/event rather than
    # through the specimen.versions association. Because every model PK is a uuid but
    # versions.item_id is bigint, PT stores item_id as id.to_i (== 0 for a uuid that
    # starts with a letter). The has_many :versions association matches item_id against
    # the uuid and therefore returns nothing. That is the known, intentionally-unfixed
    # production condition (ladder step 19) and predates this bump; these specs assert
    # PT 12 still WRITES correct rows, which is the behaviour that must not regress.
    def specimen_versions
      PaperTrail::Version.where(item_type: 'Specimen').order(:created_at)
    end

    it 'writes one version per event, populates whodunnit, and reifies the pre-update state' do
      PaperTrail.request.whodunnit = 'editor@example.org'

      specimen = nil

      # CREATE
      expect do
        specimen = create(:specimen, name: 'Original Name', plant: plant, variety: variety)
      end.to change(specimen_versions, :count).by(1)

      original_name = specimen.name
      create_version = specimen_versions.last
      expect(create_version.event).to eq('create')
      expect(create_version.whodunnit).to eq('editor@example.org')

      # UPDATE
      expect do
        specimen.update!(name: 'Updated Name')
      end.to change(specimen_versions, :count).by(1)

      update_version = specimen_versions.last
      expect(update_version.event).to eq('update')
      expect(update_version.whodunnit).to eq('editor@example.org')

      # object holds the pre-update state; it round-trips through the same serializer
      # path the app uses, and reify returns the pre-update Specimen.
      expect(PaperTrail.serializer.load(update_version.object)).to be_a(Hash)
      reified = update_version.reify
      expect(reified).to be_a(Specimen)
      expect(reified.name).to eq(original_name)

      # DESTROY
      expect do
        specimen.destroy!
      end.to change(specimen_versions, :count).by(1)

      destroy_version = specimen_versions.last
      expect(destroy_version.event).to eq('destroy')
    end

    it 'leaves whodunnit nil when the request store has none set' do
      PaperTrail.request.whodunnit = nil

      expect do
        create(:specimen, plant: plant, variety: variety)
      end.to change(specimen_versions, :count).by(1)

      expect(specimen_versions.last.whodunnit).to be_nil
    end
  end
end
