FactoryBot.define do
  factory :growth_habits_plant do
    growth_habit { build(:growth_habit) }
    plant { build(:plant) }
  end
end
