# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'plants:import', type: :task do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake.application.rake_require('tasks/plant_import', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  let(:org) { create(:organization, :real) }
  # A `real` org has no principal of its own; plants are attributed to the
  # service principal for the owner address, as production does.
  let!(:service_principal) do
    Principal.create!(kind: 'service', email: 'echo@echonet.org',
                      identity_issuer: 'spec')
  end
  let(:task) { Rake::Task['plants:import'].tap(&:reenable) }
  let(:uuid) { SecureRandom.uuid }

  # Hold a reference: a Tempfile deletes itself when garbage collected, and the
  # rake task then aborts on a missing file, which takes the whole suite with it.
  def write_fixture(records)
    @fixtures ||= []
    file = Tempfile.new(['import', '.json'])
    @fixtures << file
    file.write(JSON.generate(records))
    file.flush
    file.path
  end

  def record(overrides = {})
    {
      'uuid' => uuid,
      'scientific_name' => 'Adansonia digitata',
      'family_names' => 'Malvaceae',
      'life_cycle' => 'perennial',
      'has_edible_green_leaves' => true,
      'has_edible_immature_fruit' => false,
      'has_edible_mature_fruit' => false,
      'can_be_used_for_fodder' => false,
      'optimal_temperature_range' => '20..35',
      'ph_range' => nil,
      'common_names' => { 'EN' => [{ 'name' => 'Baobab', 'location' => nil },
                                   { 'name' => 'Monkey Bread Tree', 'location' => nil }] },
      'translations' => {
        'en' => { 'locale' => 'en', 'primary_common_name' => 'Baobab',
                  'description' => 'Short summary.',
                  'info_sheet_description' => 'The long narrative.',
                  'uses' => 'Leaves and fruit.' }
      }
    }.merge(overrides)
  end

  def run(path, apply: true)
    ClimateControl.modify(ECHO_ORG_ID: org.id, APPLY: apply ? 'true' : nil) do
      task.invoke(path)
    end
  rescue NameError
    # ClimateControl is not in this bundle; fall back to setting ENV directly.
    ENV['ECHO_ORG_ID'] = org.id
    apply ? ENV['APPLY'] = 'true' : ENV.delete('APPLY')
    task.invoke(path)
  ensure
    ENV.delete('APPLY')
    ENV.delete('ECHO_ORG_ID')
  end

  it 'creates a plant with its translations, ownership and common names' do
    expect { run(write_fixture([record])) }.to change(Plant, :count).by(1)

    plant = Plant.find(uuid)
    aggregate_failures do
      expect(plant.scientific_name).to eq 'Adansonia digitata'
      expect(plant.owner_organization_id).to eq org.id
      expect(plant.created_by_principal_id).to eq service_principal.id
      expect(plant.access_level).to eq 'public'
      expect(plant.optimal_temperature_range).to eq(20...36)
      expect(plant.description).to eq 'Short summary.'
      expect(plant.info_sheet_description).to eq 'The long narrative.'
      expect(plant.common_names.count).to eq 2
    end
  end

  it 'marks the common name matching the ECHOcommunity title as primary' do
    run(write_fixture([record]))

    names = Plant.find(uuid).common_names.index_by(&:name)
    expect(names['Baobab'].primary).to be true
    expect(names['Monkey Bread Tree'].primary).to be false
  end

  # The range columns default to values nobody measured -- ph_range to
  # '[0.0,14.0]', optimal_temperature_range to '[0,61)'. An absent range has to
  # be written as NULL or the record silently claims those tolerances.
  it 'writes absent ranges as NULL rather than accepting the column defaults' do
    run(write_fixture([record]))

    plant = Plant.find(uuid)
    aggregate_failures do
      expect(plant.ph_range).to be_nil
      expect(plant.n_accumulation_range).to be_nil
      expect(plant.biomass_production_range).to be_nil
      expect(plant.optimal_altitude_range).to be_nil
    end
  end

  it 'is idempotent: an existing uuid is skipped, not overwritten' do
    path = write_fixture([record])
    run(path)
    Plant.find(uuid).update!(scientific_name: 'Edited locally')

    expect { run(path) }.not_to change(Plant, :count)
    expect(Plant.find(uuid).scientific_name).to eq 'Edited locally'
  end

  it 'writes nothing without APPLY' do
    expect { run(write_fixture([record]), apply: false) }.not_to change(Plant, :count)
  end
end
