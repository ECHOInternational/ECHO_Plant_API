# frozen_string_literal: true

require 'rails_helper'

# The relation-set mechanism on Plant (schema-delta item 7): join rows read
# and written as one canonical string, staged on assignment, validated with
# the record, applied inside the save's transaction.
RSpec.describe RelationSets, type: :model do
  let(:plant) { create(:plant) }
  let(:leafy) { create(:category) }
  let(:fruit) { create(:category) }

  describe 'reading' do
    it "reads '[]' for a plant with no managed rows and for a new record" do
      expect(plant.category_set).to eq('[]')
      expect(plant.common_name_set).to eq('[]')
      expect(Plant.new.category_set).to eq('[]')
    end

    it 'reads the current join rows fresh, including rows written directly' do
      CategoriesPlant.create!(plant: plant, category: fruit)
      CategoriesPlant.create!(plant: plant, category: leafy)
      CommonName.create!(plant: plant, name: 'Okra', language: 'EN', primary: true)
      CommonName.create!(plant: plant, name: 'Bhindi', language: 'UND', primary: false)
      CommonName.create!(plant: plant, name: 'Gombo', language: 'FR', primary: true) # not managed
      expect(plant.category_set).to eq(JSON.generate([fruit.id, leafy.id].map(&:to_s).sort))
      expect(plant.common_name_set).to eq('[["EN","Okra",true],["UND","Bhindi",false]]')
    end

    it 'round-trips: dump(parse(read)) == read' do
      CommonName.create!(plant: plant, name: 'Okra', language: 'EN', primary: true)
      read = plant.common_name_set
      expect(RelationSets::CommonNames.dump(RelationSets::CommonNames.parse(read))).to eq(read)
    end
  end

  describe 'writing' do
    it 'stages a changed set and applies it on save' do
      plant.category_set = [leafy.id.to_s]
      expect(plant.staged_relation_sets).to have_key(:category_set)
      expect(CategoriesPlant.where(plant: plant).count).to eq(0)
      plant.save!
      expect(plant.staged_relation_sets).to be_empty
      expect(CategoriesPlant.where(plant: plant).pluck(:category_id)).to eq([leafy.id])
    end

    it 'versions each join row under the plant' do
      with_versioning do
        plant.category_set = [leafy.id.to_s]
        plant.save!
        version = PaperTrail::Version.where(item_type: 'CategoriesPlant').last
        expect(version).not_to be_nil
        expect(version.metadata).to include('root_type' => 'Plant', 'root_id' => plant.id)
      end
    end

    it 'does nothing at all when the assigned set equals the current one' do
      CategoriesPlant.create!(plant: plant, category: leafy)
      plant.category_set = JSON.generate([leafy.id.to_s])
      expect(plant.staged_relation_sets).to be_empty
      expect { plant.save! }.not_to change { PaperTrail::Version.count }
    end

    it 'accepts the canonical string as well as an array' do
      plant.category_set = JSON.generate([fruit.id.to_s])
      plant.save!
      expect(plant.category_set).to eq(JSON.generate([fruit.id.to_s]))
    end

    it 'turns an unknown category id into a validation error and writes nothing' do
      plant.category_set = ['00000000-0000-4000-8000-000000000000']
      expect(plant).not_to be_valid
      expect(plant.errors[:category_set].first).to match(/unknown category/)
      expect { plant.save! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(CategoriesPlant.where(plant: plant).count).to eq(0)
    end

    it 'rejects a malformed value at assignment time' do
      expect { plant.category_set = 'not json' }.to raise_error(JSON::ParserError)
      expect { plant.category_set = ['abc'] }.to raise_error(ArgumentError, /not a UUID/)
      expect { plant.common_name_set = [%w[EN Okra]] }.to raise_error(ArgumentError, /must be \[language, name, primary\]/)
      expect { plant.common_name_set = [['FR', 'Gombo', true]] }.to raise_error(ArgumentError, /not managed/)
    end

    it 'rolls the join rows back when a later validation fails inside the same save' do
      plant.category_set = [leafy.id.to_s]
      plant.owned_by = nil # fails validation
      expect(plant.save).to be(false)
      expect(CategoriesPlant.where(plant: plant).count).to eq(0)
    end

    it 'clears the staging on reload, as the engine does after RecordInvalid' do
      plant.category_set = [leafy.id.to_s]
      plant.reload
      expect(plant.staged_relation_sets).to be_empty
      plant.save!
      expect(CategoriesPlant.where(plant: plant).count).to eq(0)
    end

    it 'applies a set on create, when the plant has no id until it is saved' do
      fresh = build(:plant)
      fresh.common_name_set = [['EN', 'Okra', true]]
      fresh.save!
      expect(fresh.common_name_set).to eq('[["EN","Okra",true]]')
    end
  end
end
