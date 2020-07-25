FactoryBot.define do
  factory :user do
  	email { Faker::Internet.email }
  	uid { Faker::Internet.uuid }
  	trust_levels {{ "plant" => 4 }}
  	initialize_with { new(attributes.stringify_keys) }
  end
end
