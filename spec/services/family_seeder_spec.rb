# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilySeeder, type: :service do
  # A stand-in for CatalogueOfLife: FamilySeeder only ever calls #all_families
  # on its client, so a double is enough to isolate the upsert/report logic
  # under test here from the HTTP client covered by
  # spec/lib/catalogue_of_life_spec.rb.
  def stub_client(rows)
    instance_double(CatalogueOfLife, all_families: rows)
  end

  def fabaceae_row(plant_type: 'Angiosperms', col_id: '623QT')
    { name: 'Fabaceae', col_id: col_id, kingdom: 'Plantae', plant_type: plant_type }
  end

  describe '#run' do
    context 'inserting a family that does not exist yet' do
      subject(:seeder) { described_class.new(client: stub_client([fabaceae_row]), dry_run: false) }

      it 'writes the row without raising' do
        expect { seeder.run }.not_to raise_error
      end

      it 'leaves translations as an empty hash rather than NULL' do
        # This is the exact regression this spec exists for: a merged row
        # that includes translations: {} collapses to a literal SQL NULL
        # under upsert_all (see FamilySeeder#write!) and raises
        # ActiveRecord::NotNullViolation. Asserting on the persisted value
        # (not just "no error") proves the column landed at the DB default,
        # not merely that some other code path swallowed the error.
        seeder.run
        expect(Family.find_by(name: 'Fabaceae').translations).to eq({})
      end

      it 'reports the family count and a zero-dry-run report' do
        report = seeder.run
        expect(report.dry_run).to be false
        expect(report.family_count).to eq(1)
        expect(report.new_count).to eq(1)
        expect(report.existing_count).to eq(0)
      end
    end

    context 'dry run' do
      subject(:seeder) { described_class.new(client: stub_client([fabaceae_row]), dry_run: true) }

      it 'does not write anything' do
        expect { seeder.run }.not_to change(Family, :count).from(0)
      end

      it 'reports a nil family_count, since nothing was written' do
        expect(seeder.run.family_count).to be_nil
      end
    end

    context 'updating a family that already exists with curator-authored content' do
      let!(:family) do
        Family.importing { create(:family, name: 'Fabaceae', plant_type: 'Angiosperms', col_id: 'OLD1') }.tap do |f|
          Mobility.with_locale(:en) { f.description = 'Curator-written description' }
          f.seed_banking_rank = 4
          f.save!
        end
      end

      subject(:seeder) do
        described_class.new(
          client: stub_client([fabaceae_row(plant_type: 'Gymnosperms', col_id: 'NEW2')]),
          version: 'COL27.1 XR',
          dry_run: false
        )
      end

      it 'does not create a second row' do
        expect { seeder.run }.not_to change(Family, :count).from(1)
      end

      it 'preserves curator-authored description and seed_banking_rank untouched' do
        seeder.run
        family.reload
        expect(family.description).to eq('Curator-written description')
        expect(family.seed_banking_rank).to eq(4)
      end

      it 'still refreshes taxonomic facts sourced from COL, proving the upsert is not a no-op' do
        seeder.run
        family.reload
        expect(family.plant_type).to eq('Gymnosperms')
        expect(family.col_id).to eq('NEW2')
        expect(family.classification_version).to eq('COL27.1 XR')
      end

      it 'reports the row as already present, not new' do
        report = seeder.run
        expect(report.new_count).to eq(0)
        expect(report.existing_count).to eq(1)
      end
    end
  end
end
