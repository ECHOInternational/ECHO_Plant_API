FactoryBot.define do
  factory :categories_plant do
    category { build(:category) }
    plant { build(:plant) }
  end
end
