# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ImageAttribute lookup mutations', type: :graphql_mutation do
  before :each do
    Mobility.locale = nil
  end

  it_behaves_like 'a lookup create mutation', model: ImageAttribute
  it_behaves_like 'a lookup update mutation', model: ImageAttribute, factory: :image_attribute
  it_behaves_like 'a lookup delete mutation', model: ImageAttribute, factory: :image_attribute
end
