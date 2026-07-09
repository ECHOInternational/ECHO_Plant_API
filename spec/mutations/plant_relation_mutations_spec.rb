# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Plant relation set mutations', type: :graphql_mutation do
  it_behaves_like 'a relation set mutation',
                  field_name: 'updatePlantCategories', owner_factory: :plant, owner_key: 'plant',
                  items_factory: :category, ids_key: 'categoryIds', association: :categories
  it_behaves_like 'a relation set mutation',
                  field_name: 'updatePlantTolerances', owner_factory: :plant, owner_key: 'plant',
                  items_factory: :tolerance, ids_key: 'toleranceIds', association: :tolerances
  it_behaves_like 'a relation set mutation',
                  field_name: 'updatePlantGrowthHabits', owner_factory: :plant, owner_key: 'plant',
                  items_factory: :growth_habit, ids_key: 'growthHabitIds', association: :growth_habits
  it_behaves_like 'a relation set mutation',
                  field_name: 'updatePlantAntinutrients', owner_factory: :plant, owner_key: 'plant',
                  items_factory: :antinutrient, ids_key: 'antinutrientIds', association: :antinutrients
end
