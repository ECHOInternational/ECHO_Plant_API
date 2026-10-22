# frozen_string_literal: true

require 'rails_helper'
require 'support/publication_wave_helpers'

RSpec.describe PublicationWaves::Publisher do
  include PublicationWaveHelpers

  let!(:rich) { source_plant(text: 600) }
  let!(:pictured) { source_plant.tap { |p| plant_image(p) } }
  let!(:thin) { source_plant }
  let!(:echo_plant) { create(:plant, :public) }

  def publisher(**)
    described_class.new(data_source: wave_source, key: 'fpi-w1', selector: 'quality', **)
  end

  def dry_run(**)
    publisher(**).run
  end

  def apply(**opts)
    digest = dry_run(**opts.except(:notes)).digest
    publisher(apply: true, expected_digest: digest, **opts).run
  end

  describe 'selection' do
    def selected(**)
      PublicationWaves::Selector.new(data_source: wave_source, selector: 'quality', **).select.plant_ids
    end

    it 'takes the plants that meet the rule' do
      expect(selected).to contain_exactly(rich.id, pictured.id)
    end

    it 'takes every eligible plant with selector remaining, and named ones with ids' do
      expect(selected(selector: 'remaining')).to contain_exactly(rich.id, pictured.id, thin.id)
      expect(selected(selector: 'ids', ids: [thin.id.upcase, echo_plant.id])).to eq([thin.id])
    end

    it 'keeps the first N by id with a limit' do
      expect(selected(selector: 'remaining', limit: '2')).to eq([rich.id, pictured.id, thin.id].sort.first(2))
    end

    it 'leaves out plants of other sources or owners, deleted, draft and public ones' do
      other_owner = source_plant(text: 600, owner_organization_id: create(:organization, :real).id)
      deleted = source_plant(text: 600).tap { |p| p.update!(visibility: :deleted) }
      draft = source_plant(text: 600).tap { |p| p.update!(visibility: :draft) }
      public = source_plant(text: 600).tap { |p| p.update!(visibility: :public) }
      expect(selected(selector: 'remaining')).not_to include(other_owner.id, deleted.id, draft.id, public.id, echo_plant.id)
    end

    it 'leaves out plants with an open source_deletion conflict, but not with a resolved one or a content conflict' do
      create(:sync_conflict, :source_deletion, syncable: rich, data_source: wave_source)
      create(:sync_conflict, :source_deletion, :resolved, syncable: pictured, data_source: wave_source)
      create(:sync_conflict, syncable: thin, data_source: wave_source)
      selection = PublicationWaves::Selector.new(data_source: wave_source, selector: 'remaining').select
      expect(selection.plant_ids).to contain_exactly(pictured.id, thin.id)
      expect(selection.excluded).to eq('in_active_wave' => 0, 'open_source_deletion' => 1)
    end

    it 'refuses unknown selectors, empty ids, a bad limit, and quality without a rule' do
      expect { selected(selector: 'all') }.to raise_error(PublicationWaves::Refused, /unknown selector/)
      expect { selected(selector: 'ids', ids: []) }.to raise_error(PublicationWaves::Refused, /IDS/)
      expect { selected(limit: 'ten') }.to raise_error(PublicationWaves::Refused, /LIMIT/)
      expect { selected(limit: '0') }.to raise_error(PublicationWaves::Refused, /LIMIT/)
      wave_source.update!(publication_rule: nil)
      expect { selected }.to raise_error(PublicationWaves::Refused, /publication_rule/)
    end

    it 'changes the digest when the selection or its images change' do
      first = PublicationWaves::Selector.new(data_source: wave_source, selector: 'quality').select.digest
      expect(PublicationWaves::Selector.new(data_source: wave_source, selector: 'quality').select.digest).to eq(first)
      plant_image(rich)
      expect(PublicationWaves::Selector.new(data_source: wave_source, selector: 'quality').select.digest).not_to eq(first)
    end
  end

  describe 'dry run' do
    it 'counts and writes nothing' do
      plant_image(pictured, :draft)
      before = visibility_state
      result = dry_run
      expect(result.applied).to be(false)
      expect(result.digest).to match(/\A\h{64}\z/)
      expect(result.counts).to include('plants' => 2, 'images' => 1, 'open_drafts' => 0)
      expect(visibility_state).to eq(before)
      expect(PublicationWave.count).to eq(0)
    end

    it 'counts safety flags, twins of public plants from another source, and open drafts' do
      rich.update!(safety_level: 'poisonous')
      pictured.update!(edibility_uncertain: true)
      create(:plant, :public, scientific_name: "  #{rich.scientific_name.upcase}  ")
      create(:record_draft, draftable: pictured)
      expect(dry_run.counts).to include('safety_poisonous' => 1, 'safety_caution' => 0, 'edibility_uncertain_only' => 1,
                                        'echo_twins' => 1, 'open_drafts' => 1)
    end

    it 'refuses a malformed key and notes holding an email address' do
      expect { described_class.new(data_source: wave_source, key: 'FPI W1', selector: 'quality') }
        .to raise_error(PublicationWaves::Refused, /key/)
      expect { publisher(notes: 'from someone@example.org') }.to raise_error(PublicationWaves::Refused, /'@'/)
    end
  end

  describe 'apply' do
    it 'refuses without the digest, or with a digest that no longer matches' do
      expect { publisher(apply: true).run }.to raise_error(PublicationWaves::Refused, /EXPECTED_DIGEST is required/)
      expect { publisher(apply: true, expected_digest: 'f' * 64).run }.to raise_error(PublicationWaves::Refused, /does not match/)
      expect(PublicationWave.count).to eq(0)
      expect(rich.reload.visibility).to eq('private')
    end

    it 'publishes the selected plants and their private images, and records the ledger' do
      image = pictured.images.first
      draft_image = plant_image(pictured, :draft)
      result = apply(notes: 'wave one')

      expect(result.applied).to be(true)
      wave = result.wave
      expect(wave).to have_attributes(state: 'applied', selector: 'quality', notes: 'wave one', rule_snapshot: PublicationWaveHelpers::WAVE_RULE)
      [rich, pictured].each do |plant|
        expect(plant.reload).to have_attributes(visibility: 'public', access_level: 'public', publication_state: 'published')
      end
      expect(thin.reload.visibility).to eq('private')
      expect(image.reload.visibility).to eq('public')
      expect(draft_image.reload.visibility).to eq('draft')

      plant_item = wave.items.find_by(item_type: 'Plant', item_id: rich.id)
      expect(plant_item).to have_attributes(state: 'applied', origin: 'publish')
      expect(plant_item.prior).to eq('visibility' => 0, 'publication_state' => 'published', 'access_level' => 'organization',
                                     'deleted_at' => nil)
      expect(plant_item.applied).to include('visibility' => 1, 'access_level' => 'public')
      expect(wave.items.find_by(item_type: 'Image', item_id: image.id)).to have_attributes(
        plant_id: pictured.id, state: 'applied', prior: { 'visibility' => 0 }, applied: { 'visibility' => 1 }
      )
      expect(result.counts['items']).to eq('Image publish applied' => 1, 'Plant publish applied' => 2)
    end

    it 'attributes each change to the ops principal and writes no touch version on the plant' do
      with_versioning do
        result = apply
        principal = PublicationWaves.ops_principal!
        expect(principal).to have_attributes(identity_issuer: 'ops', kind: 'service')

        plant_versions = PaperTrail::Version.where(item_type: 'Plant', item_id: pictured.id)
        expect(plant_versions.count).to eq(1)
        version = plant_versions.first
        expect(version.whodunnit).to eq(principal.id)
        expect(version.metadata).to include('origin' => 'wave_publish', 'wave_id' => result.wave.id, 'wave_key' => 'fpi-w1',
                                            'data_source_id' => wave_source.id)

        image_version = PaperTrail::Version.find_by(item_type: 'Image', item_id: pictured.images.first.id)
        expect(image_version.metadata).to include('origin' => 'wave_publish', 'root_type' => 'Plant', 'root_id' => pictured.id)
        expect(PaperTrail::Version.where(item_type: 'PublicationWaveItem')).not_to exist
      end
    end

    it 'does nothing more when run again on an applied wave' do
      apply
      before = [visibility_state, PublicationWaveItem.count]
      again = publisher(apply: true, expected_digest: PublicationWave.last.selection_digest).run
      expect(again).to have_attributes(applied: false, resumed: true)
      expect([visibility_state, PublicationWaveItem.count]).to eq(before)
    end

    it 'resumes an interrupted wave with the same digest' do
      digest = dry_run.digest
      calls = 0
      allow_any_instance_of(Plant).to receive(:save!).and_wrap_original do |original, *args, **kwargs|
        calls += 1
        raise 'connection lost' if calls == 2

        original.call(*args, **kwargs)
      end
      expect { publisher(apply: true, expected_digest: digest).run }.to raise_error(RuntimeError, 'connection lost')

      wave = PublicationWave.find_by!(key: 'fpi-w1')
      expect(wave.state).to eq('applying')
      expect(wave.items.where(item_type: 'Plant').group(:state).count).to eq('applied' => 1, 'pending' => 1)
      expect(Plant.where(id: [rich.id, pictured.id]).visibility_public.count).to eq(1)

      result = publisher(apply: true, expected_digest: digest).run
      expect(result.resumed).to be(true)
      expect(wave.reload.state).to eq('applied')
      expect(Plant.where(id: [rich.id, pictured.id]).visibility_public.count).to eq(2)
      expect(pictured.images.first.reload.visibility).to eq('public')
    end

    it 'skips a plant that stopped being eligible after the wave was created' do
      digest = dry_run.digest
      allow(PublicationWaveItem).to receive(:insert_all!).and_wrap_original do |original, rows|
        original.call(rows).tap { rich.update!(visibility: :draft) }
      end
      publisher(apply: true, expected_digest: digest).run
      expect(PublicationWave.last.items.find_by(item_id: rich.id).state).to eq('skipped')
      expect(rich.reload.visibility).to eq('draft')
    end

    it 'excludes the plants of an active wave from the next one, and refuses to reuse an unpublished key' do
      apply
      rich.reload.update!(visibility: :private) # an editor took it back; it stays in wave fpi-w1
      next_wave = PublicationWaves::Selector.new(data_source: wave_source, selector: 'remaining').select
      expect(next_wave.plant_ids).to eq([thin.id])
      expect(next_wave.excluded['in_active_wave']).to eq(1)
      PublicationWave.last.update!(state: 'unpublished')
      expect { dry_run }.to raise_error(PublicationWaves::Refused, /unpublished; publish a new wave/)
    end
  end
end
