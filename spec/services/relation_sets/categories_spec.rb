# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RelationSets::Categories do
  let(:plant) { create(:plant) }
  let(:a) { create(:category) }
  let(:b) { create(:category) }

  describe '.parse' do
    it 'lower-cases, de-duplicates and sorts UUID strings' do
      upper = a.id.to_s.upcase
      expect(described_class.parse([upper, b.id.to_s, a.id.to_s])).to eq([a.id.to_s, b.id.to_s].sort)
      expect(described_class.parse(JSON.generate([b.id.to_s]))).to eq([b.id.to_s])
    end

    it 'refuses anything that is not a UUID string' do
      expect { described_class.parse(['nope']) }.to raise_error(ArgumentError, /not a UUID/)
      expect { described_class.parse([1]) }.to raise_error(ArgumentError, /UUID string/)
      expect { described_class.parse('"x"') }.to raise_error(ArgumentError, /must be an array/)
    end
  end

  describe '.validate' do
    it 'names every unknown id' do
      ghost = '00000000-0000-4000-8000-000000000000'
      expect(described_class.validate(plant, [a.id.to_s])).to eq([])
      expect(described_class.validate(plant, [a.id.to_s, ghost])).to eq(["refers to an unknown category #{ghost}"])
    end
  end

  describe '.apply' do
    it 'replaces the set: creates the missing joins and destroys the extra ones' do
      CategoriesPlant.create!(plant: plant, category: a)
      described_class.apply(plant, [b.id.to_s])
      expect(CategoriesPlant.where(plant: plant).pluck(:category_id)).to eq([b.id])
      expect(Category.exists?(a.id)).to be(true)
    end

    it 'reads back what it wrote' do
      described_class.apply(plant, [a.id.to_s, b.id.to_s].sort)
      expect(described_class.read(plant)).to eq(JSON.generate([a.id.to_s, b.id.to_s].sort))
    end
  end
end
