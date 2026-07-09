# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GrowthHabit lookup mutations', type: :graphql_mutation do
  before :each do
    Mobility.locale = nil
  end

  it_behaves_like 'a lookup create mutation', model: GrowthHabit
  it_behaves_like 'a lookup update mutation', model: GrowthHabit, factory: :growth_habit
  it_behaves_like 'a lookup delete mutation', model: GrowthHabit, factory: :growth_habit
end
