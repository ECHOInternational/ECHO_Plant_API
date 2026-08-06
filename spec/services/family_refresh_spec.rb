# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyRefresh, type: :service do
  before do
    Family.importing do
      create(:family, name: 'Malvaceae', col_id: 'CDB')
      create(:family, name: 'Tiliaceae', col_id: 'H9G')
    end
  end

  def upstream(*names)
    names.map { |n| { name: n, col_id: "X#{n}", kingdom: 'Plantae', plant_type: 'Angiosperms' } }
  end

  # A stand-in for CatalogueOfLife: #diff calls #synonym_lookup once per
  # vanished name. Defaults every name to :not_found so a test that does not
  # care about classification (and never sets up a `responses` entry) still
  # gets a safe, network-free answer instead of falling through to the real
  # HTTP client.
  def stub_client(responses = {})
    client = instance_double(CatalogueOfLife)
    allow(client).to receive(:synonym_lookup) { |name| responses.fetch(name, { status: :not_found }) }
    client
  end

  it 'reports a family that is new upstream' do
    diff = described_class.new(upstream('Malvaceae', 'Tiliaceae', 'Brassicaceae')).diff
    expect(diff[:added].map { |r| r[:name] }).to eq(['Brassicaceae'])
  end

  it 'reports a family that has vanished upstream' do
    diff = described_class.new(upstream('Malvaceae'), client: stub_client).diff
    expect(diff[:vanished].map(&:name)).to eq(['Tiliaceae'])
  end

  it 'counts the plants affected by a vanished family' do
    tiliaceae = Family.find_by(name: 'Tiliaceae')
    create(:plant, family: tiliaceae)
    diff = described_class.new(upstream('Malvaceae'), client: stub_client).diff
    expect(diff[:affected_plant_counts]['Tiliaceae']).to eq(1)
  end

  it 'applies nothing during a diff' do
    described_class.new(upstream('Malvaceae'), client: stub_client).diff
    expect(Family.find_by(name: 'Tiliaceae')).to be_present
    expect(Family.find_by(name: 'Tiliaceae').status).to eq('accepted')
  end

  # The rename/merge/split/no-successor gap: #diff used to lump every
  # vanished name into one bucket, offering only apply_merge as a
  # remediation regardless of what actually happened upstream. Each example
  # below drives #diff with a stubbed CatalogueOfLife#synonym_lookup result
  # and checks the vanished family lands in exactly the bucket that result
  # implies -- never guessed, never silently dropped.
  describe 'classifying why a family vanished' do
    it 'classifies a synonym whose target is itself new this release as a rename candidate' do
      client = stub_client('Tiliaceae' => { status: :synonym, accepted_name: 'Neoteliaceae' })
      diff = described_class.new(upstream('Malvaceae', 'Neoteliaceae'), client: client).diff

      expect(diff[:renamed_candidates].map { |c| c[:family].name }).to eq(['Tiliaceae'])
      expect(diff[:renamed_candidates].first[:target_name]).to eq('Neoteliaceae')
      expect(diff[:merge_candidates]).to be_empty
      expect(diff[:split_candidates]).to be_empty
      expect(diff[:no_successor]).to be_empty
    end

    it 'classifies a synonym whose target is a family we already hold as a merge candidate' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      create(:plant, family: tiliaceae)
      client = stub_client('Tiliaceae' => { status: :synonym, accepted_name: 'Malvaceae' })

      diff = described_class.new(upstream('Malvaceae'), client: client).diff

      candidate = diff[:merge_candidates].first
      expect(diff[:merge_candidates].map { |c| c[:family].name }).to eq(['Tiliaceae'])
      expect(candidate[:target_name]).to eq('Malvaceae')
      expect(candidate[:plant_count]).to eq(1)
    end

    it 'classifies an ambiguous synonym (no single successor) as a split candidate' do
      client = stub_client('Tiliaceae' => { status: :ambiguous_synonym })
      diff = described_class.new(upstream('Malvaceae'), client: client).diff

      expect(diff[:split_candidates].map { |c| c[:family].name }).to eq(['Tiliaceae'])
      expect(diff[:split_candidates].first[:target_name]).to be_nil
    end

    it 'classifies a genuine disappearance with no synonym as no_successor' do
      client = stub_client('Tiliaceae' => { status: :not_found })
      diff = described_class.new(upstream('Malvaceae'), client: client).diff

      expect(diff[:no_successor].map { |c| c[:family].name }).to eq(['Tiliaceae'])
    end

    it 'falls back to no_successor, never guessing, when the lookup raises' do
      client = instance_double(CatalogueOfLife)
      allow(client).to receive(:synonym_lookup).and_raise(StandardError, 'network exploded')

      diff = described_class.new(upstream('Malvaceae'), client: client).diff

      expect(diff[:no_successor].map { |c| c[:family].name }).to eq(['Tiliaceae'])
    end

    it 'falls back to no_successor when the lookup itself reports :error rather than raising' do
      client = stub_client('Tiliaceae' => { status: :error })
      diff = described_class.new(upstream('Malvaceae'), client: client).diff

      expect(diff[:no_successor].map { |c| c[:family].name }).to eq(['Tiliaceae'])
    end

    it 'falls back to no_successor, with the target still reported, if a synonym target matches nothing we know' do
      client = stub_client('Tiliaceae' => { status: :synonym, accepted_name: 'Ghostaceae' })
      diff = described_class.new(upstream('Malvaceae'), client: client).diff

      expect(diff[:no_successor].map { |c| c[:family].name }).to eq(['Tiliaceae'])
      expect(diff[:no_successor].first[:target_name]).to eq('Ghostaceae')
    end

    it 'never calls the lookup for a name that still exists upstream' do
      client = instance_double(CatalogueOfLife)
      expect(client).not_to receive(:synonym_lookup)

      described_class.new(upstream('Malvaceae', 'Tiliaceae'), client: client).diff
    end
  end

  # The col_id hazard carried forward from Task 9's review: families.col_id
  # has its own unique partial index, separate from the lower(name) index
  # this diff matches on. A newer COL release can hand a "new" family name a
  # col_id that some existing local row already holds (an id migrating off
  # the row it used to belong to), which would otherwise abort the whole
  # Family.importing transaction with a hard uniqueness violation.
  describe 'the col_id collision hazard' do
    it 'reports rather than proposes writing a family whose col_id is already taken locally' do
      rows = upstream('Malvaceae', 'Tiliaceae') + [
        { name: 'Brassicaceae', col_id: 'CDB', kingdom: 'Plantae', plant_type: 'Angiosperms' }
      ]

      diff = described_class.new(rows).diff

      expect(diff[:added]).to be_empty
      expect(diff[:col_id_conflicts].map { |r| r[:name] }).to eq(['Brassicaceae'])
    end

    it 'reports only the first of two new families that arrive sharing one col_id' do
      rows = upstream('Malvaceae', 'Tiliaceae') + [
        { name: 'Brassicaceae', col_id: 'NEWID', kingdom: 'Plantae', plant_type: 'Angiosperms' },
        { name: 'Rosaceae', col_id: 'NEWID', kingdom: 'Plantae', plant_type: 'Angiosperms' }
      ]

      diff = described_class.new(rows).diff

      expect(diff[:added].map { |r| r[:name] }).to eq(['Brassicaceae'])
      expect(diff[:col_id_conflicts].map { |r| r[:name] }).to eq(['Rosaceae'])
    end

    it 'does not treat a blank col_id as a conflict' do
      rows = upstream('Malvaceae', 'Tiliaceae') + [
        { name: 'Brassicaceae', col_id: nil, kingdom: 'Plantae', plant_type: 'Angiosperms' }
      ]

      diff = described_class.new(rows).diff

      expect(diff[:added].map { |r| r[:name] }).to eq(['Brassicaceae'])
      expect(diff[:col_id_conflicts]).to be_empty
    end
  end

  describe '#apply_merge' do
    it 'repoints plants and supersedes the old family' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      malvaceae = Family.find_by(name: 'Malvaceae')
      plant = create(:plant, family: tiliaceae)

      described_class.new([]).apply_merge(tiliaceae, malvaceae)

      expect(plant.reload.family).to eq(malvaceae)
      expect(tiliaceae.reload.status).to eq('superseded')
      expect(tiliaceae.superseded_by).to eq(malvaceae)
    end

    it 'keeps the superseded row so nothing dangles' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      described_class.new([]).apply_merge(tiliaceae, Family.find_by(name: 'Malvaceae'))
      expect(Family.find_by(name: 'Tiliaceae')).to be_present
    end
  end

  describe '#apply_rename' do
    it 'renames the family in place, keeping its own row and every plant link untouched' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      plant = create(:plant, family: tiliaceae)
      original_id = tiliaceae.id

      described_class.new([]).apply_rename(tiliaceae, 'Neoteliaceae')

      tiliaceae.reload
      expect(tiliaceae.id).to eq(original_id)
      expect(tiliaceae.name).to eq('Neoteliaceae')
      expect(tiliaceae.status).to eq('accepted')
      expect(plant.reload.family).to eq(tiliaceae)
    end

    it 'does not supersede or touch superseded_by, unlike a merge' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      described_class.new([]).apply_rename(tiliaceae, 'Neoteliaceae')

      expect(tiliaceae.reload.superseded_by).to be_nil
    end
  end

  describe '#apply_additions!' do
    it 'writes the added rows as accepted families' do
      diff = described_class.new(upstream('Malvaceae', 'Tiliaceae', 'Brassicaceae')).diff
      count = described_class.new([]).apply_additions!(diff[:added], version: 'COL26.7 XR',
                                                                     snapshot_date: Date.new(2026, 7, 17))

      expect(count).to eq(1)
      expect(Family.find_by(name: 'Brassicaceae')).to be_present
    end

    it 'leaves translations as an empty hash rather than NULL' do
      # Mirrors the exact regression FamilySeeder guards against: an explicit
      # translations: {} in the merged row collapses to a literal SQL NULL
      # under upsert_all and raises ActiveRecord::NotNullViolation, so the
      # key must be omitted and left to the column default instead.
      diff = described_class.new(upstream('Malvaceae', 'Tiliaceae', 'Brassicaceae')).diff
      described_class.new([]).apply_additions!(diff[:added], version: 'COL26.7 XR',
                                                             snapshot_date: Date.new(2026, 7, 17))

      expect(Family.find_by(name: 'Brassicaceae').translations).to eq({})
    end

    it 'does nothing for an empty list' do
      expect(described_class.new([]).apply_additions!([])).to eq(0)
    end

    # Belt-and-suspenders regression for the col_id hazard: even if a caller
    # bypasses #diff's own filtering and hands apply_additions! a row whose
    # col_id collides with an existing family, the failure must be a clear,
    # rescued error -- never a raw, unexplained PG::UniqueViolation bubbling
    # out of the middle of the Family.importing transaction.
    it 'raises a clear error rather than an unexplained crash if a col_id collision reaches the write' do
      colliding_row = { name: 'Brassicaceae', col_id: 'CDB', kingdom: 'Plantae', plant_type: 'Angiosperms' }

      expect do
        described_class.new([]).apply_additions!([colliding_row], version: 'COL26.7 XR',
                                                                  snapshot_date: Date.new(2026, 7, 17))
      end.to raise_error(FamilyRefresh::ColIdCollisionError, /CDB/)
    end
  end

  # The reviewer's IMPORTANT-1 finding: a rename target is ALWAYS present in
  # #diff's upstream batch with no local match (that is exactly why
  # classify_synonym calls it a rename in the first place), so leaving it in
  # +added+ meant apply_additions! always inserted it as a fresh, plant-less
  # row before the rename ran, and the rename then collided with that row on
  # index_families_on_lower_name. This spec drives the whole sequence a real
  # operator would: read the diff, apply additions, then apply the rename.
  describe 'the full rename-then-additions sequence' do
    it 'keeps a rename appliable after additions for the same release have already been applied' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      plant = create(:plant, family: tiliaceae)
      client = stub_client('Tiliaceae' => { status: :synonym, accepted_name: 'Neoteliaceae' })
      rows = upstream('Malvaceae', 'Neoteliaceae', 'Brassicaceae')

      refresh = described_class.new(rows, client: client)
      diff = refresh.diff

      # The rename target must never be in the added set: it belongs to
      # apply_rename, not apply_additions!.
      expect(diff[:added].map { |r| r[:name] }).to eq(['Brassicaceae'])
      expect(diff[:renamed_candidates].first[:target_name]).to eq('Neoteliaceae')

      added = refresh.apply_additions!(diff[:added], version: 'COL26.7 XR', snapshot_date: Date.new(2026, 7, 17))
      expect(added).to eq(1)
      expect(Family.find_by(name: 'Neoteliaceae')).to be_nil

      expect { refresh.apply_rename(tiliaceae, 'Neoteliaceae') }.not_to raise_error
      expect(tiliaceae.reload.name).to eq('Neoteliaceae')
      expect(plant.reload.family).to eq(tiliaceae)
    end
  end

  # The reviewer's IMPORTANT-2 finding: apply_additions! upserted with no
  # update_only at all, so a name COL resurrects after we already merged it
  # away landed in +added+ (Family.accepted does not include a superseded
  # row) and the upsert flipped status back to accepted while leaving
  # superseded_by_id pointing at the family that absorbed it. Splitting a
  # resurrection into its own bucket is meant to make that impossible: added
  # additions never touch an existing row's status at all.
  describe 'a Catalogue of Life resurrection' do
    it 'never treats a re-accepted, previously superseded family as a plain addition' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      malvaceae = Family.find_by(name: 'Malvaceae')
      plant = create(:plant, family: tiliaceae)
      described_class.new([]).apply_merge(tiliaceae, malvaceae)

      refresh = described_class.new(upstream('Malvaceae', 'Tiliaceae'))
      diff = refresh.diff

      expect(diff[:added]).to be_empty
      expect(diff[:resurrected].map { |c| c[:family] }).to eq([tiliaceae])

      refresh.apply_additions!(diff[:added])

      tiliaceae.reload
      expect(tiliaceae.status).to eq('superseded')
      expect(tiliaceae.superseded_by).to eq(malvaceae)
      expect(plant.reload.family).to eq(malvaceae)
    end

    describe '#apply_resurrection!' do
      it 're-accepts the family and clears the dangling superseded_by_id without repointing plants back' do
        tiliaceae = Family.find_by(name: 'Tiliaceae')
        malvaceae = Family.find_by(name: 'Malvaceae')
        plant = create(:plant, family: tiliaceae)
        described_class.new([]).apply_merge(tiliaceae, malvaceae)

        refresh = described_class.new(upstream('Malvaceae', 'Tiliaceae'))
        candidate = refresh.diff[:resurrected].first

        refresh.apply_resurrection!(candidate, version: 'COL26.8 XR', snapshot_date: Date.new(2026, 8, 17))

        tiliaceae.reload
        expect(tiliaceae.status).to eq('accepted')
        expect(tiliaceae.superseded_by_id).to be_nil
        expect(tiliaceae.classification_version).to eq('COL26.8 XR')
        # The merge already decided these plants belong under malvaceae; a
        # resurrection is not evidence about any individual plant, so it must
        # not repoint them back.
        expect(plant.reload.family).to eq(malvaceae)
      end

      it 'preserves curator-authored metadata, since apply_additions! never touches this row at all' do
        tiliaceae = Family.find_by(name: 'Tiliaceae')
        Mobility.with_locale(:en) { tiliaceae.description = 'Curator note' }
        tiliaceae.save!
        described_class.new([]).apply_merge(tiliaceae, Family.find_by(name: 'Malvaceae'))

        refresh = described_class.new(upstream('Malvaceae', 'Tiliaceae'))
        candidate = refresh.diff[:resurrected].first
        refresh.apply_resurrection!(candidate)

        expect(tiliaceae.reload.description).to eq('Curator note')
      end
    end
  end

  describe FamilyRefresh::Report do
    it 'renders the vanished families and any col_id conflicts for a human to review' do
      rows = upstream('Malvaceae') + [
        { name: 'Brassicaceae', col_id: 'CDB', kingdom: 'Plantae', plant_type: 'Angiosperms' }
      ]
      diff = FamilyRefresh.new(rows, client: stub_client).diff

      text = described_class.new(diff).to_s

      expect(text).to include('Tiliaceae')
      expect(text).to include('Brassicaceae')
      expect(text).to include('col_id')
    end

    it 'renders each of the four vanished-classification buckets distinctly, with a verify-before-applying legend' do
      client = stub_client('Tiliaceae' => { status: :synonym, accepted_name: 'Malvaceae' })
      diff = FamilyRefresh.new(upstream('Malvaceae'), client: client).diff

      text = described_class.new(diff).to_s

      expect(text).to include('MERGE CANDIDATES')
      expect(text).to include('Tiliaceae -> Malvaceae')
      expect(text).to include('verify against COL')
      expect(text).to include('apply_rename')
      expect(text).to include('apply_merge')
    end

    it 'omits a bucket section entirely when nothing falls into it' do
      diff = FamilyRefresh.new(upstream('Malvaceae', 'Tiliaceae')).diff

      text = described_class.new(diff).to_s

      expect(text).not_to include('RENAME CANDIDATES')
      expect(text).not_to include('MERGE CANDIDATES')
      expect(text).not_to include('SPLIT CANDIDATES')
      expect(text).not_to include('NO SUCCESSOR')
    end

    it 'reports a resurrection distinctly, pointing at apply_resurrection! rather than APPLY=1' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      FamilyRefresh.new([]).apply_merge(tiliaceae, Family.find_by(name: 'Malvaceae'))

      diff = FamilyRefresh.new(upstream('Malvaceae', 'Tiliaceae')).diff
      text = described_class.new(diff).to_s

      expect(text).to include('RESURRECTED')
      expect(text).to include('Tiliaceae (was superseded by Malvaceae)')
      expect(text).to include('apply_resurrection!')
    end
  end
end
