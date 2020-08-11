FactoryBot.define do
  factory :image do
    id { Faker::Internet.uuid }
    sequence(:name) { |n| "image#{n}" }
    description { "<h1>Lorem ipsum dolor sit amet, consectetur adipisicing elit.</h1><p>Velit, libero nulla! Magni amet, reiciendis iste. Placeat eligendi magni recusandae aspernatur suscipit, rem maxime impedit velit, nam, consequuntur commodi! Hic, repellendus.</p>" }
    created_by { Faker::Internet.email }
    owned_by { Faker::Internet.email }
    attribution { Faker::Lorem.paragraph }
    s3_bucket { "images-us-east-1.echocommunity.org" }
    sequence("s3_key") { |n| "image#{n}.jpg" }
    imageable { create(:category) }
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
