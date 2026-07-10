# frozen_string_literal: true

require 'rails_helper'
# Migration classes are not autoloaded; require each migration so specs can pin the
# exact extraction SQL each uses.
require Rails.root.join('db', 'migrate', '20260710000000_repair_versions_item_id_to_uuid')
require Rails.root.join('db', 'migrate', '20260710000001_backfill_versions_item_id_quoted_uuids')

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

    # Adversarial case 1: `plant_id` tuple appears BEFORE the `id` tuple in the payload.
    # Without the `(?n)^` line-start anchor, `plant_id:\n-\n- <uuid>` would match the
    # unanchored pattern `id:\n-\n- <uuid>` (substring returns leftmost occurrence, which
    # would be the plant_id's uuid rather than the record's own uuid).
    # With line-anchoring, only the line that begins exactly with `id:` matches.
    it 'extracts the record uuid when the id tuple appears after a plant_id tuple' do
      plant_uuid = 'aaaa1234-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      # id: tuple is ordinal-2 in this payload (plant_id comes first).
      object_changes = "---\nplant_id:\n-\n- #{plant_uuid}\nid:\n-\n- #{known_uuid}\nname:\n-\n- Galangal\n"
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

      # Must return the record's OWN uuid, not plant_id's uuid.
      expect(extracted).to eq(known_uuid)
      expect(extracted).not_to eq(plant_uuid)
    end

    # Adversarial case 2: payload has a `plant_id` tuple but NO `id` tuple.
    # The unanchored pattern would still match and return the plant_id's uuid (wrong).
    # The line-anchored pattern must return NULL (no `id:` line exists at line-start).
    it 'returns NULL when the payload has plant_id but no id tuple' do
      plant_uuid = 'bbbb5678-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      # No `id:` change tuple - only plant_id.
      object_changes = "---\nplant_id:\n-\n- #{plant_uuid}\nname:\n-\n- Galangal\n"
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

      # Must return NULL - no `id:` at line start means no record uuid to extract.
      expect(extracted).to be_nil
    end
  end

  # Pre-promo 2b: pins the QUOTED-uuid patterns introduced in
  # BackfillVersionsItemIdQuotedUuids (20260710000001). Old-era PaperTrail YAML
  # single-quotes the uuid value:
  #
  #   object:          id: '06283413-7115-4abd-9147-1a47f17749c5'
  #   object_changes:  id:\n- \n- '06283413-7115-4abd-9147-1a47f17749c5'
  #
  # The v2 patterns are a STRICT SUPERSET: they accept both quoted and bare uuids.
  describe 'v2 quote-tolerant extraction (BackfillVersionsItemIdQuotedUuids constants)' do
    # Anonymized uuid from the real staging payload evidence documented in the brief.
    let(:quoted_uuid) { '06283413-7115-4abd-9147-1a47f17749c5' }
    let(:bare_uuid)   { 'de68e499-3ff6-4954-b3fa-8ec754923b74' }

    # ---- OBJECT_SQL_V2 --------------------------------------------------------

    it 'extracts a single-quoted uuid from an object payload (old-era YAML)' do
      # Old PaperTrail YAML: id: '06283413-...'
      object_payload = "---\nid: '#{quoted_uuid}'\nowned_by: user@example.org\nname: Galangal\n"
      version = PaperTrail::Version.create!(
        item_type: 'Specimen',
        event: 'update',
        object: object_payload
      )
      expect(version.item_id).to be_nil

      extracted = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT #{BackfillVersionsItemIdQuotedUuids::ITEM_ID_FROM_OBJECT_SQL_V2}
          FROM versions
         WHERE id = #{version.id}
      SQL

      expect(extracted).to eq(quoted_uuid)
    end

    it 'also extracts a bare uuid from an object payload (v2 is a superset of v1)' do
      object_payload = "---\nid: #{bare_uuid}\nname: Galangal\n"
      version = PaperTrail::Version.create!(
        item_type: 'Specimen',
        event: 'update',
        object: object_payload
      )

      extracted = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT #{BackfillVersionsItemIdQuotedUuids::ITEM_ID_FROM_OBJECT_SQL_V2}
          FROM versions
         WHERE id = #{version.id}
      SQL

      expect(extracted).to eq(bare_uuid)
    end

    # ---- OBJECT_CHANGES_SQL_V2 ------------------------------------------------

    it 'extracts a single-quoted uuid from an object_changes create-tuple (dash-SPACE shape)' do
      # Real staging payload shape: nil line is `- ` (dash-SPACE), uuid is single-quoted.
      object_changes = "---\nid:\n- \n- '#{quoted_uuid}'\nname:\n-\n- Galangal\n"
      version = PaperTrail::Version.create!(
        item_type: 'Specimen',
        event: 'create',
        object_changes: object_changes
      )
      expect(version.item_id).to be_nil

      extracted = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT #{BackfillVersionsItemIdQuotedUuids::ITEM_ID_FROM_OBJECT_CHANGES_SQL_V2}
          FROM versions
         WHERE id = #{version.id}
      SQL

      expect(extracted).to eq(quoted_uuid)
    end

    it 'extracts a single-quoted uuid from an object_changes create-tuple (bare-dash shape)' do
      # Alternate nil-line spelling without trailing space.
      object_changes = "---\nid:\n-\n- '#{quoted_uuid}'\nname:\n-\n- Galangal\n"
      version = PaperTrail::Version.create!(
        item_type: 'Specimen',
        event: 'create',
        object_changes: object_changes
      )

      extracted = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT #{BackfillVersionsItemIdQuotedUuids::ITEM_ID_FROM_OBJECT_CHANGES_SQL_V2}
          FROM versions
         WHERE id = #{version.id}
      SQL

      expect(extracted).to eq(quoted_uuid)
    end

    it 'also extracts a bare uuid from an object_changes create-tuple (v2 is a superset of v1)' do
      object_changes = "---\nid:\n-\n- #{bare_uuid}\nname:\n-\n- Galangal\n"
      version = PaperTrail::Version.create!(
        item_type: 'Specimen',
        event: 'create',
        object_changes: object_changes
      )

      extracted = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT #{BackfillVersionsItemIdQuotedUuids::ITEM_ID_FROM_OBJECT_CHANGES_SQL_V2}
          FROM versions
         WHERE id = #{version.id}
      SQL

      expect(extracted).to eq(bare_uuid)
    end
  end
end
