FactoryBot.define do
  factory :plant do
    scientific_name { Faker::Creature::Animal.name }
    family_names { Faker::Creature::Animal.name }
    has_edible_green_leaves { false }
    has_edible_immature_fruit { false }
    has_edible_mature_fruit { false }
    can_be_used_for_fodder { false }
    description { '<h1>Lorem ipsum dolor sit amet, consectetur adipisicing elit.</h1><p>Velit, libero nulla! Magni amet, reiciendis iste. Placeat eligendi magni recusandae aspernatur suscipit, rem maxime impedit velit, nam, consequuntur commodi! Hic, repellendus.</p>' }
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
