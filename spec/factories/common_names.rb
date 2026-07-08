# frozen_string_literal: true

FactoryBot.define do
  factory :common_name do
    name { Faker::Creature::Animal.name }
    language { 'EN' }
    primary { false }
    plant
  end
end
