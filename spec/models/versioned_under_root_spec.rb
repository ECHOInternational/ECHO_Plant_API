# frozen_string_literal: true

require 'rails_helper'

# Child rows stamp their history root into versions.metadata so a plant's
# timeline can pick them up with one containment query.
#
# The controller supplies metadata too (origin, principal_id) through
# PaperTrail.request.controller_info, and paper_trail 17 lets controller info
# REPLACE a model-level meta: value for the same key. These examples pin the
# requirement that both survive.
RSpec.describe VersionedUnderRoot, type: :model do
  def versions_for(record)
    PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).order(:id)
  end

  describe 'stamping', versioning: true do
    it 'records the plant root on a common name create' do
      plant = create(:plant)
      common_name = create(:common_name, plant: plant, name: 'Test Name')

      metadata = versions_for(common_name).last.metadata
      expect(metadata['root_type']).to eq 'Plant'
      expect(metadata['root_id']).to eq plant.id
    end

    it 'keeps the controller metadata alongside the root reference' do
      principal = create(:principal)
      plant = create(:plant)

      common_name = nil
      PaperTrail.request(
        whodunnit: principal.id,
        controller_info: { metadata: { origin: 'api', principal_id: principal.id } }
      ) do
        common_name = create(:common_name, plant: plant)
      end

      metadata = versions_for(common_name).last.metadata
      expect(metadata['origin']).to eq 'api'
      expect(metadata['principal_id']).to eq principal.id
      expect(metadata['root_type']).to eq 'Plant'
      expect(metadata['root_id']).to eq plant.id
    end

    it 'records the plant root when a join row is destroyed' do
      plant = create(:plant)
      category = create(:category)
      link = CategoriesPlant.create!(plant: plant, category: category)
      link.destroy!

      destroy_version = PaperTrail::Version
                        .where(item_type: 'CategoriesPlant', item_id: link.id, event: 'destroy')
                        .last
      expect(destroy_version.metadata['root_type']).to eq 'Plant'
      expect(destroy_version.metadata['root_id']).to eq plant.id
    end

    it 'records the variety root on a variety join row' do
      variety = create(:variety)
      tolerance = create(:tolerance)
      link = TolerancesVariety.create!(variety: variety, tolerance: tolerance)

      metadata = versions_for(link).last.metadata
      expect(metadata['root_type']).to eq 'Variety'
      expect(metadata['root_id']).to eq variety.id
    end

    it 'records the plant root for an image attached to a plant' do
      plant = create(:plant)
      image = create(:image, imageable: plant)

      metadata = versions_for(image).last.metadata
      expect(metadata['root_type']).to eq 'Plant'
      expect(metadata['root_id']).to eq plant.id
    end

    it 'leaves images on other parents unstamped' do
      specimen = create(:specimen)
      image = create(:image, imageable: specimen)

      expect(versions_for(image).last.metadata).to be_blank
    end
  end
end
