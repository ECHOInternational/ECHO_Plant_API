# frozen_string_literal: true

require 'rails_helper'
# Migration classes are not autoloaded; require it so the spec can pin the exact
# extraction SQL the migration uses.
require Rails.root.join('db', 'migrate', '20260710000000_repair_versions_item_id_to_uuid')

# Tripwire for the versions.item_id repair (pre-promotion step P2).
#
# Historically every model PK is a uuid but versions.item_id was bigint, so
# PaperTrail stored record.id.to_i (== 0, or leading digits of the uuid) and the
# polymorphic `record.versions` association matched nothing. The P2 migration
# converts item_id to uuid and backfills the true id out of the YAML payloads.
#
# This spec pins two things that must not regress:
#   1. LIVE: a create/update cycle writes item_id == record.id (the uuid string),
#      the `record.versions` association returns those rows, and reify works.
#   2. BACKFILL SHAPE: the migration's extraction SQL, run against the committed
#      PT-10-era fixture payload, recovers the fixture's known uuid. This pins the
#      regex against the real payload shape so a serializer/format change is caught.
RSpec.describe 'PaperTrail versions.item_id repair', type: :model do
  describe 'live versioning writes and returns rows by item_id', versioning: true do
    let(:plant) { create(:plant) }

    it 'stores item_id == specimen.id and makes the versions association resolve' do
      specimen = nil

      # CREATE
      expect do
        specimen = create(:specimen, name: 'Original', plant: plant)
      end.to change { specimen&.versions&.count.to_i }.from(0).to(1)

      create_version = specimen.versions.last
      expect(create_version.event).to eq('create')
      # The repaired column carries the real uuid, not 0.
      expect(create_version.item_id).to eq(specimen.id)

      # UPDATE: the association (item_id polymorphic match) now returns the row.
      expect do
        specimen.update!(name: 'Updated')
      end.to change { specimen.versions.count }.from(1).to(2)

      expect(specimen.versions.pluck(:item_id).uniq).to eq([specimen.id])

      # reify still round-trips through the live association.
      reified = specimen.versions.last.reify
      expect(reified).to be_a(Specimen)
    end
  end

  describe 'backfill extraction expression (regex pinned to fixture payload shape)' do
    let(:fixture_object) do
      File.read(Rails.root.join('spec', 'fixtures', 'paper_trail', 'specimen_version_object_pt10.yml'))
    end
    let(:known_uuid) { 'de68e499-3ff6-4954-b3fa-8ec754923b74' }

    it 'recovers the fixture uuid from a NULL-item_id row via the object regex' do
      # Insert a row the OLD way: item_id NULL (post-migration column is nullable
      # uuid), object = the committed PT-10 fixture text.
      version = PaperTrail::Version.create!(
        item_type: 'Specimen',
        event: 'update',
        object: fixture_object
      )
      expect(version.item_id).to be_nil

      # Run the migration's exact object-extraction SQL against that row.
      extracted = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT #{RepairVersionsItemIdToUuid::ITEM_ID_FROM_OBJECT_SQL}
          FROM versions
         WHERE id = #{version.id}
      SQL

      expect(extracted).to eq(known_uuid)
    end

    it 'recovers a uuid from an object_changes create-tuple via the changes regex' do
      # A creation-shaped object_changes payload (PaperTrail emits `id:\n-\n- <uuid>`).
      object_changes = "---\nid:\n-\n- #{known_uuid}\nname:\n-\n- Galangal\n"
      version = PaperTrail::Version.create!(
        item_type: 'Specimen',
        event: 'create',
        object_changes: object_changes
      )

      extracted = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT #{RepairVersionsItemIdToUuid::ITEM_ID_FROM_OBJECT_CHANGES_SQL}
          FROM versions
         WHERE id = #{version.id}
      SQL

      expect(extracted).to eq(known_uuid)
    end
  end
end
