# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyReconciler, type: :service do
  let!(:fabaceae) { Family.importing { create(:family, name: 'Fabaceae') } }
  let!(:cucurbitaceae) { Family.importing { create(:family, name: 'Cucurbitaceae') } }

  # A stand-in for FamilyResolver: FamilyReconciler only ever calls #resolve
  # on it, so a double is enough to isolate the classification decision tree
  # under test here from the GBIF HTTP client covered by
  # spec/lib/family_resolver_spec.rb.
  def stub_resolver(responses)
    resolver = instance_double(FamilyResolver)
    responses.each { |name, result| allow(resolver).to receive(:resolve).with(name).and_return(result) }
    resolver
  end

  def local(family)
    { family: family, via: :local, confidence: nil }
  end

  def unresolved
    { family: nil, via: :unresolved, confidence: nil }
  end

  def gbif_corrected(family, confidence)
    { family: family, via: :gbif_corrected, confidence: confidence, spelling: family.name }
  end

  describe '#run' do
    context 'a blank family_names value' do
      let!(:plant) { create(:plant, family_names: nil) }
      let(:resolver) { stub_resolver({}) }
      subject(:reconciler) { described_class.new(resolver: resolver, dry_run: true, scope: Plant.where(id: plant.id)) }

      it 'is left null, not sent to review' do
        report = reconciler.run
        expect(report.blank.map { |r| r[:plant] }).to eq([plant])
        expect(report.review).to be_empty
        expect(report.applied).to be_empty
      end
    end

    context 'a clean local hit' do
      let!(:plant) { create(:plant, family_names: 'Fabaceae') }
      let(:resolver) { stub_resolver('Fabaceae' => local(fabaceae)) }
      subject(:reconciler) { described_class.new(resolver: resolver, dry_run: true, scope: Plant.where(id: plant.id)) }

      it 'is applied' do
        report = reconciler.run
        expect(report.applied).to eq([{ plant: plant, status: :applied, family: fabaceae,
                                        results: [local(fabaceae)] }])
      end

      it 'does not write in dry-run mode' do
        expect { reconciler.run }.not_to change { plant.reload.family_id }.from(nil)
      end
    end

    context 'a live run' do
      let!(:plant) { create(:plant, family_names: 'Fabaceae') }
      let(:resolver) { stub_resolver('Fabaceae' => local(fabaceae)) }
      subject(:reconciler) { described_class.new(resolver: resolver, dry_run: false, scope: Plant.where(id: plant.id)) }

      it 'writes family_id via update_columns, applying the confident match' do
        reconciler.run
        expect(plant.reload.family_id).to eq(fabaceae.id)
      end
    end

    context 'a low-confidence GBIF correction' do
      let!(:plant) { create(:plant, family_names: 'Curcurbitaceae') }
      let(:resolver) { stub_resolver('Curcurbitaceae' => gbif_corrected(cucurbitaceae, 5)) }
      subject(:reconciler) do
        described_class.new(resolver: resolver, min_confidence: 80, dry_run: true, scope: Plant.where(id: plant.id))
      end

      it 'is routed to review rather than auto-applied, below the confidence floor' do
        report = reconciler.run
        expect(report.applied).to be_empty
        row = report.review.first
        expect(row[:plant]).to eq(plant)
        expect(row[:reason]).to eq(:low_confidence)
        expect(row[:family]).to eq(cucurbitaceae)
      end
    end

    context 'an unresolved value' do
      let!(:plant) { create(:plant, family_names: 'Leguminaceae') }
      let(:resolver) { stub_resolver('Leguminaceae' => unresolved) }
      subject(:reconciler) { described_class.new(resolver: resolver, dry_run: true, scope: Plant.where(id: plant.id)) }

      it 'is routed to review as unresolved_or_conflicting' do
        report = reconciler.run
        expect(report.applied).to be_empty
        row = report.review.first
        expect(row[:plant]).to eq(plant)
        expect(row[:reason]).to eq(:unresolved_or_conflicting)
      end
    end

    context 'a multi-candidate record whose candidates disagree' do
      let!(:plant) { create(:plant, family_names: 'Fabaceae Or Cucurbitaceae') }
      let(:resolver) do
        stub_resolver('Fabaceae' => local(fabaceae), 'Cucurbitaceae' => local(cucurbitaceae))
      end
      subject(:reconciler) { described_class.new(resolver: resolver, dry_run: true, scope: Plant.where(id: plant.id)) }

      it 'is routed to review as unresolved_or_conflicting, not applied to either family' do
        report = reconciler.run
        expect(report.applied).to be_empty
        row = report.review.first
        expect(row[:plant]).to eq(plant)
        expect(row[:reason]).to eq(:unresolved_or_conflicting)
      end
    end
  end
end
