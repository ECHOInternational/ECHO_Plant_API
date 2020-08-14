# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Antinutrient, type: :model do
  it 'is valid with valid attributes' do
    antinutrient = build(:antinutrient)
    expect(antinutrient).to be_valid
  end
  it 'is not valid without a name' do
    antinutrient = build(:antinutrient, name: nil)
    expect(antinutrient).to_not be_valid
  end
  it 'translates the name attribute' do
    antinutrient = create(:antinutrient, name_en: 'name_en')
    antinutrient.name_es = 'name_es'
    expect(antinutrient.translations).to have_key(:en)
    expect(antinutrient.translations).to have_key(:es)
    expect(antinutrient.translations[:en]).to have_key(:name)
    expect(antinutrient.translations[:es]).to have_key(:name)
    expect(antinutrient.translations[:en][:name]).to eq('name_en')
    expect(antinutrient.translations[:es][:name]).to eq('name_es')
  end
end
