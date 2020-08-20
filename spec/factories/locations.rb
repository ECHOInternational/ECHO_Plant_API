FactoryBot.define do
  factory :location do
    sequence(:name) { |n| "Location #{n}" }
    latlng { ActiveRecord::Point.new(26.640629, -81.872307) }
    area { 0.25 }
    soil_quality { 1 }
    slope { rand(90) }
    altitude { rand(8848) }
    average_rainfall { rand(990) }
    average_temperature { rand(40) }
    irrigated { false }
    notes { Faker::Lorem.paragraph }
    created_by { Faker::Internet.email }
    owned_by { Faker::Internet.email }
    trait :public do
      visibility { :public }
    end
    trait :draft do
      visibility { :draft }
    end
    trait :deleted do
      visibility { :deleted }
    end
    trait :private do
      visibility { :private }
    end
  end
end
