# frozen_string_literal: true

require 'rails_helper'

# Verification of the suspected defect recorded as risk R5 in the plant-data
# ownership migration roadmap.
#
# SourceSynchronizer#compare_and_sync reads local state with
#
#   local = record.attributes.slice(*@source_attributes)
#
# `record.attributes` returns ActiveRecord's column-backed attributes. Mobility
# is configured with `backend :container` and WITHOUT the `attribute_methods`
# plugin (config/initializers/mobility.rb), so translated attributes such as
# `description` live inside the `translations` jsonb and never appear in
# `attributes`. For a translated source attribute the local side therefore reads
# as {} on every run.
#
# The existing suite never catches this: SOURCE_ATTRS is
# %w[scientific_name family_names], both real columns, and the one spec that
# passes %w[description] exercises the invalid-payload path, which returns
# before compare_and_sync.
#
# Predicted consequence: a re-sync of unchanged data is scored as
# `locally_modified` rather than `synced`, and a genuine upstream change is
# never applied. Translated fields would silently stop syncing after creation.
RSpec.describe SourceSynchronizer, 'with a Mobility-translated source attribute' do
  let(:org)         { create(:organization, :real) }
  let(:data_source) { create(:data_source, organization: org) }
  let(:run_id)      { SecureRandom.hex(8) }

  def sync(attrs)
    SourceSynchronizer.new(
      data_source: data_source,
      model: Plant,
      source_attributes: attrs,
      run_id: run_id
    )
  end

  def row(description:, source_record_id: 'tr-1', source_updated_at: 1.day.ago)
    {
      source_record_id: source_record_id,
      deleted: false,
      attributes: { 'description' => description },
      source_updated_at: source_updated_at
    }
  end

  it 'confirms the mechanism: a translated attribute is absent from #attributes' do
    plant = create(:plant, owner_organization_id: org.id, source_organization_id: org.id,
                           description: 'Some description')

    expect(plant.description).to eq 'Some description'
    expect(plant.attributes).to have_key('translations')
    expect(plant.attributes).not_to have_key('description'),
                                    'if this fails, Mobility now exposes translated attrs and the defect is gone'
    expect(plant.attributes.slice('description')).to eq({})
  end

  it 'scores an identical re-run as synced, not locally_modified' do
    batch = [row(description: 'A stable description')]

    first = sync(%w[description]).apply(batch)
    expect(first.created).to eq(1), 'expected the first run to create the record'

    second = sync(%w[description]).apply(batch)

    plant = Plant.find_by(source_record_id: 'tr-1')
    aggregate_failures do
      expect(second.locally_modified).to eq(0),
                                         'nobody edited this record, so it must not be scored locally_modified'
      expect(second.synced).to eq(1)
      expect(plant.sync_state).to eq 'synced'
    end
  end

  it 'applies a genuine upstream change to a translated attribute' do
    sync(%w[description]).apply([row(description: 'Original text')])

    changed = sync(%w[description]).apply(
      [row(description: 'Updated upstream text', source_updated_at: 1.hour.ago)]
    )

    plant = Plant.find_by(source_record_id: 'tr-1')
    aggregate_failures do
      expect(changed.applied).to eq(1), 'an upstream edit must reach the record'
      expect(plant.description).to eq 'Updated upstream text'
    end
  end
end
