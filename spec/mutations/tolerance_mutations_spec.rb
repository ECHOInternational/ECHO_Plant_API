# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tolerance lookup mutations', type: :graphql_mutation do
  before :each do
    Mobility.locale = nil
  end

  it_behaves_like 'a lookup create mutation', model: Tolerance
  it_behaves_like 'a lookup update mutation', model: Tolerance, factory: :tolerance
  it_behaves_like 'a lookup delete mutation', model: Tolerance, factory: :tolerance
end
