# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::Subject, versioning: true do
  def last_version(record)
    PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).order(:id).last
  end

  it 'labels the record itself' do
    plant = create(:plant)
    subject = described_class.new(last_version(plant))

    expect(subject.subject_type).to eq 'record'
    expect(subject.label).to be_nil
  end

  it 'labels a common name with its name' do
    common_name = create(:common_name, name: 'Sample Name')
    subject = described_class.new(last_version(common_name))

    expect(subject.subject_type).to eq 'common_name'
    expect(subject.label).to eq 'Sample Name'
  end

  it 'labels a deleted common name from the destroy changeset' do
    common_name = create(:common_name, name: 'Removed Name')
    common_name.destroy!
    version = PaperTrail::Version.where(item_type: 'CommonName', item_id: common_name.id, event: 'destroy').last

    subject = described_class.new(version)
    expect(subject.subject_type).to eq 'common_name'
    expect(subject.label).to eq 'Removed Name'
  end

  it 'labels a join row with the linked lookup name' do
    category = create(:category, name: 'Legumes')
    link = CategoriesPlant.create!(plant: create(:plant), category: category)

    subject = described_class.new(last_version(link))
    expect(subject.subject_type).to eq 'category'
    expect(subject.label).to eq 'Legumes'
  end

  it 'falls back to nil when the linked row is gone' do
    tolerance = create(:tolerance)
    link = TolerancesPlant.create!(plant: create(:plant), tolerance: tolerance)
    version = last_version(link)
    link.destroy!
    tolerance.destroy!

    subject = described_class.new(version)
    expect(subject.subject_type).to eq 'tolerance'
    expect(subject.label).to be_nil
  end

  it 'labels an image with its name' do
    image = create(:image, name: 'Field photo')

    subject = described_class.new(last_version(image))
    expect(subject.subject_type).to eq 'image'
    expect(subject.label).to eq 'Field photo'
  end
end
