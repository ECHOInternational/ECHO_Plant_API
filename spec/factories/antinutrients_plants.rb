FactoryBot.define do
  factory :antinutrients_plant do
    antinutrient { build(:antinutrient) }
    plant { build(:plant) }
  end
end
