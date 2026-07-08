# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Antinutrient lookup mutations', type: :graphql_mutation do
  before :each do
    Mobility.locale = nil
  end

  it_behaves_like 'a lookup create mutation', model: Antinutrient
  it_behaves_like 'a lookup update mutation', model: Antinutrient, factory: :antinutrient
  it_behaves_like 'a lookup delete mutation', model: Antinutrient, factory: :antinutrient
end
