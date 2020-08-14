# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tolerance, type: :model do
  it 'is valid with valid attributes' do
    tolerance = build(:tolerance)
    expect(tolerance).to be_valid
  end
  it 'is not valid without a name' do
    tolerance = build(:tolerance, name: nil)
    expect(tolerance).to_not be_valid
  end
  it 'translates the name attribute' do
    tolerance = create(:tolerance, name_en: 'name_en')
    tolerance.name_es = 'name_es'
    expect(tolerance.translations).to have_key(:en)
    expect(tolerance.translations).to have_key(:es)
    expect(tolerance.translations[:en]).to have_key(:name)
    expect(tolerance.translations[:es]).to have_key(:name)
    expect(tolerance.translations[:en][:name]).to eq('name_en')
    expect(tolerance.translations[:es][:name]).to eq('name_es')
  end
end
