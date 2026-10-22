# frozen_string_literal: true

require 'rails_helper'
require 'support/publication_wave_helpers'

RSpec.describe PublicationWaves::Unpublisher do
  include PublicationWaveHelpers
  include ActiveSupport::Testing::TimeHelpers

  let!(:rich) { source_plant(text: 600) }
  let!(:pictured) { source_plant.tap { |p| plant_image(p) } }
  let!(:thin) { source_plant }
  let!(:old_public_image) { plant_image(rich, :public) }

  def publish!(key = 'fpi-w1')
    selection = PublicationWaves::Selector.new(data_source: wave_source, selector: 'quality').select
    PublicationWaves::Publisher.new(data_source: wave_source, key: key, selector: 'quality', apply: true,
                                    expected_digest: selection.digest).run.wave
  end

  def unpublish(apply: false, key: 'fpi-w1')
    described_class.new(data_source: wave_source, key: key, apply: apply).run
  end

  it 'restores exactly what the wave changed' do
    before = visibility_state
    publish!
    expect(visibility_state).not_to eq(before)

    result = unpublish(apply: true)
    expect(result.applied).to be(true)
    expect(visibility_state).to eq(before)
    expect(result.wave).to have_attributes(state: 'unpublished')
    expect(result.wave.unpublished_at).to be_present
    expect(result.counts['items']).to eq('Image publish restored' => 1, 'Plant publish restored' => 2)
    expect(old_public_image.reload.visibility).to eq('public')
  end

  it 'previews in a dry run and changes nothing' do
    publish!
    published = visibility_state
    result = unpublish
    expect(result.applied).to be(false)
    expect(result.counts['preview']).to eq('Image would be restored' => 1, 'Image would be swept' => 0,
                                           'Plant would be restored' => 2)
    expect(visibility_state).to eq(published)
    expect(PublicationWave.last.state).to eq('applied')
  end

  it 'leaves rows changed since the wave alone and counts them as drift' do
    publish!
    rich.reload.update!(visibility: :draft)
    pictured.images.first.update!(visibility: :deleted)

    expect(unpublish.counts['preview']).to include('Plant would be drift' => 1, 'Image would be drift' => 1)
    result = unpublish(apply: true)
    expect(result.counts['items']).to include('Plant publish drift' => 1, 'Image publish drift' => 1, 'Plant publish restored' => 1)
    expect(rich.reload.visibility).to eq('draft')
    expect(pictured.images.first.reload.visibility).to eq('deleted')
    expect(pictured.reload.visibility).to eq('private')
  end

  it 'makes private the public images added to a wave plant after the wave started' do
    before = visibility_state
    wave = publish!
    late = travel_to(1.minute.from_now) { plant_image(pictured, :public) }

    expect(unpublish.counts['preview']).to include('Image would be swept' => 1)
    unpublish(apply: true)

    expect(late.reload.visibility).to eq('private')
    expect(wave.items.find_by(item_id: late.id)).to have_attributes(origin: 'unpublish_sweep', state: 'restored',
                                                                    prior: { 'visibility' => 1 }, applied: { 'visibility' => 0 })
    expect(visibility_state.last - [[late.id, 'private', pictured.id]]).to eq(before.last)
  end

  it 'tolerates items whose rows were deleted (FpiRollback with FORCE_PUBLIC)' do
    publish!
    Image.where(imageable_id: pictured.id).delete_all
    Plant.unscoped.where(id: pictured.id).delete_all

    result = unpublish(apply: true)
    expect(result.counts['items']).to include('Plant publish missing' => 1, 'Image publish missing' => 1,
                                              'Plant publish restored' => 1)
    expect(rich.reload.visibility).to eq('private')
  end

  it 'does nothing more on an unpublished wave, and lets a new wave publish the plants again' do
    publish!
    unpublish(apply: true)
    state = visibility_state
    expect(unpublish(apply: true).applied).to be(false)
    expect(visibility_state).to eq(state)

    again = publish!('fpi-w1-again')
    expect(again.items.where(item_type: 'Plant').pluck(:plant_id)).to contain_exactly(rich.id, pictured.id)
  end

  it 'attributes the restoring versions to the ops principal' do
    with_versioning do
      publish!
      unpublish(apply: true)
      version = PaperTrail::Version.where(item_type: 'Plant', item_id: rich.id).order(:id).last
      expect(version.whodunnit).to eq(PublicationWaves.ops_principal!.id)
      expect(version.metadata).to include('origin' => 'wave_unpublish', 'wave_key' => 'fpi-w1')
      expect(PaperTrail::Version.where(item_type: 'Plant', item_id: pictured.id).count).to eq(2)
    end
  end

  it 'refuses an unknown wave or a wave of another source' do
    expect { unpublish }.to raise_error(PublicationWaves::Refused, /no wave/)
    publish!
    other = create(:data_source)
    expect { described_class.new(data_source: other, key: 'fpi-w1').run }
      .to raise_error(PublicationWaves::Refused, /another data source/)
  end
end
