# frozen_string_literal: true

require 'rails_helper'

# Guards the PERMITTED_CLASSES entry for ActiveRecord::Point.
#
# Location#latlng is a Postgres `point` column that Rails materialises as
# ActiveRecord::Point (a Struct). PaperTrail serialises it to a tagged YAML
# node (`!ruby/struct:ActiveRecord::Point`). Without ActiveRecord::Point in the
# safe_load permitted_classes list, calling `version.reify` on any Location
# version that carried coordinates would raise Psych::DisallowedClass (a 500).
# This spec creates a Location with coordinates, updates those coordinates, and
# asserts that `versions.last.reify` returns the pre-update point without raising.
RSpec.describe 'PaperTrail ActiveRecord::Point reify', type: :model do
  def location_versions
    PaperTrail::Version.where(item_type: 'Location').order(:created_at)
  end

  describe 'reifying a Location version that contains coordinates', versioning: true do
    it 'returns the pre-update coordinates without raising Psych::DisallowedClass' do
      original_point = ActiveRecord::Point.new(1.5, 2.5)
      updated_point  = ActiveRecord::Point.new(9.9, 8.8)

      location = create(:location, latlng: original_point)

      expect do
        location.update!(latlng: updated_point)
      end.to change(location_versions, :count).by(1)

      update_version = location_versions.last
      expect(update_version.event).to eq('update')

      # Must not raise Psych::DisallowedClass; must return the pre-update state.
      reified = update_version.reify
      expect(reified).to be_a(Location)
      expect(reified.latlng.x).to eq(1.5)
      expect(reified.latlng.y).to eq(2.5)
    end
  end
end
