# frozen_string_literal: true

require 'rails_helper'

# The safety concept, the scientific-name authority, and the habitat/notes
# translations added for the Food Plants International import (fpi-connector
# schema-delta items 5, 6 and 17).
RSpec.describe Plant, type: :model do
  describe 'safety_level' do
    it "defaults to 'none', which records no warning rather than asserting safety" do
      plant = create(:plant)
      expect(plant.safety_level).to eq('none')
      expect(plant).to be_safety_none
      expect(plant.safety_warning).to be(false)
      expect(plant.reload.safety_warning).to be(false)
    end

    it 'accepts caution and poisonous and derives the warning from the level' do
      plant = create(:plant, safety_level: 'caution')
      expect(plant.safety_warning).to be(true)
      expect(plant.reload.safety_warning).to be(true)
      plant.update!(safety_level: :poisonous)
      expect(plant.reload).to be_safety_poisonous
      expect(plant.safety_warning).to be(true)
    end

    it 'turns an unknown level into a validation error, not an ArgumentError' do
      plant = build(:plant)
      expect { plant.safety_level = 'lethal' }.not_to raise_error
      expect(plant).not_to be_valid
      expect(plant.errors[:safety_level]).to be_present
    end

    it 'is enforced by a database CHECK constraint as well' do
      plant = create(:plant)
      expect do
        Plant.where(id: plant.id).update_all(safety_level: 'lethal')
      end.to raise_error(ActiveRecord::StatementInvalid, /plants_safety_level_check/)
    end

    it 'cannot have the generated warning column written directly' do
      plant = create(:plant, safety_level: 'caution')
      expect do
        Plant.where(id: plant.id).update_all(safety_warning: false)
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe 'edibility_uncertain' do
    it 'defaults to false and is independent of the level' do
      plant = create(:plant)
      expect(plant.edibility_uncertain).to be(false)
      plant.update!(edibility_uncertain: true)
      expect(plant.reload.edibility_uncertain).to be(true)
      expect(plant.safety_level).to eq('none')
    end
  end

  describe 'scientific_name_authority' do
    it "stores a blank as NULL and reads it back as ''" do
      plant = create(:plant, scientific_name_authority: '')
      expect(plant.reload.scientific_name_authority).to be_nil
      expect(plant.scientific_name_authority.to_s).to eq('')
    end

    it 'keeps the citation verbatim and never folds it into the name' do
      plant = create(:plant, scientific_name: 'Abelmoschus moschatus', scientific_name_authority: '(L.) Merr.')
      expect(plant.reload.scientific_name_authority).to eq('(L.) Merr.')
      expect(plant.scientific_name).to eq('Abelmoschus moschatus')
    end
  end

  describe 'the new translated attributes' do
    it 'translates safety_note, habitat and notes like every other prose field' do
      plant = create(:plant, safety_note_en: 'Seeds (POISONOUS)', habitat_en: 'A tropical plant.', notes_en: 'n')
      plant.habitat_es = 'Una planta tropical.'
      expect(plant.translations[:en]).to include(safety_note: 'Seeds (POISONOUS)', habitat: 'A tropical plant.', notes: 'n')
      expect(plant.translations[:es]).to include(habitat: 'Una planta tropical.')
      en = plant.translations_array.find { |t| t[:locale] == 'en' }
      expect(en).to include(safety_note: 'Seeds (POISONOUS)', habitat: 'A tropical plant.', notes: 'n')
    end
  end

  describe 'draftable and history registries' do
    it 'lists the new columns as draftable' do
      expect(DraftableAttributes::PLANT).to include('scientific_name_authority', 'safety_level', 'edibility_uncertain')
      expect(DraftableAttributes::PLANT).not_to include('safety_warning')
    end

    it 'renders safety_level as an enum in history diffs' do
      expect(ChangeHistory::DiffBuilder::ENUM_COLUMNS).to include('safety_level')
    end
  end
end
