# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Variety relation set mutations', type: :graphql_mutation do
  it_behaves_like 'a relation set mutation',
                  field_name: 'updateVarietyTolerances', owner_factory: :variety, owner_key: 'variety',
                  items_factory: :tolerance, ids_key: 'toleranceIds', association: :tolerances
  it_behaves_like 'a relation set mutation',
                  field_name: 'updateVarietyGrowthHabits', owner_factory: :variety, owner_key: 'variety',
                  items_factory: :growth_habit, ids_key: 'growthHabitIds', association: :growth_habits
  it_behaves_like 'a relation set mutation',
                  field_name: 'updateVarietyAntinutrients', owner_factory: :variety, owner_key: 'variety',
                  items_factory: :antinutrient, ids_key: 'antinutrientIds', association: :antinutrients
end
