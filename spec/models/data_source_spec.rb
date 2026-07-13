# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataSource, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      expect(build(:data_source)).to be_valid
    end

    it "is not valid without a name" do
      expect(build(:data_source, name: nil)).not_to be_valid
    end

    it "is not valid without a source_system_key" do
      expect(build(:data_source, source_system_key: nil)).not_to be_valid
    end

    it "is not valid without an organization" do
      ds = build(:data_source)
      ds.organization = nil
      expect(ds).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to an organization" do
      ds = create(:data_source)
      expect(ds.organization).to be_a(Organization)
    end
  end
end
