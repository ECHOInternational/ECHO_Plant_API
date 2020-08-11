FactoryBot.define do
  factory :image_attribute do
    name { ['Full Plant', 'Leaf', 'Stem', 'Roots'].sample }
  end
end
