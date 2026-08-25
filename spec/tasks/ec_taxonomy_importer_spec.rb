# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/ec_taxonomy_importer')

RSpec.describe EcTaxonomyImporter do
  let(:org) { create(:organization, :real) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end
  let(:tolerance) { create(:tolerance) }
  let(:antinutrient) { create(:antinutrient) }

  def import(taxonomies, apply: true)
    described_class.new(apply: apply).import(taxonomies)
  end

  it 'links a plant to a lookup row' do
    result = import({ 'tolerances' => { plant.id => [tolerance.id] } })

    expect(result.linked).to eq 1
    expect(plant.reload.tolerances.map(&:id)).to eq [tolerance.id]
  end

  it 'handles all three taxonomies in one payload' do
    habit = create(:growth_habit)
    result = import({ 'tolerances' => { plant.id => [tolerance.id] },
                      'antinutrients' => { plant.id => [antinutrient.id] },
                      'growth_habits' => { plant.id => [habit.id] } })

    expect(result.linked).to eq 3
    plant.reload
    expect(plant.tolerances.count).to eq 1
    expect(plant.antinutrients.count).to eq 1
    expect(plant.growth_habits.count).to eq 1
  end

  it 'does not duplicate a link that already exists' do
    import({ 'tolerances' => { plant.id => [tolerance.id] } })
    result = import({ 'tolerances' => { plant.id => [tolerance.id] } })

    expect(result.linked).to eq 0
    expect(result.present).to eq 1
    expect(plant.reload.tolerances.count).to eq 1
  end

  # These are curated taxonomies. A uuid that is not already there means the
  # payload and the database disagree, which must surface rather than be created.
  it 'reports an unknown lookup uuid and creates nothing' do
    ghost = SecureRandom.uuid
    result = import({ 'tolerances' => { plant.id => [ghost] } })

    expect(result.unknown_lookups).to eq ["tolerances: #{ghost}"]
    expect(result.linked).to eq 0
    expect(Tolerance.exists?(id: ghost)).to be false
  end

  it 'skips a plant that is not in this database' do
    result = import({ 'tolerances' => { SecureRandom.uuid => [tolerance.id] } })

    expect(result.missing_plants).to eq 1
    expect(result.failed).to eq 0
  end

  it 'rejects an unknown taxonomy name rather than guessing' do
    result = import({ 'nutrients' => { plant.id => [tolerance.id] } })

    expect(result.failed).to eq 1
    expect(result.errors.first).to include 'unknown taxonomy: nutrients'
  end

  # Removing an assignment is an editorial act, not a migration one.
  it 'is additive: a lookup the payload omits stays linked' do
    other = create(:tolerance)
    import({ 'tolerances' => { plant.id => [tolerance.id, other.id] } })
    import({ 'tolerances' => { plant.id => [tolerance.id] } })

    expect(plant.reload.tolerances.count).to eq 2
  end

  it 'writes nothing on a dry run' do
    result = import({ 'tolerances' => { plant.id => [tolerance.id] } }, apply: false)

    expect(result.linked).to eq 1
    expect(plant.reload.tolerances).to be_empty
  end
end
