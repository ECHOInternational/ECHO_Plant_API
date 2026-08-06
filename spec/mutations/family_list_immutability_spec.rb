# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'the family list is immutable through GraphQL', type: :request do
  let(:mutation_fields) { PlantApiSchema.mutation.fields.keys }

  it 'exposes no mutation that creates a family' do
    expect(mutation_fields).not_to include('createFamily')
  end

  it 'exposes no mutation that deletes a family' do
    expect(mutation_fields).not_to include('deleteFamily')
  end

  it 'exposes exactly one family mutation' do
    expect(mutation_fields.grep(/[Ff]amily/)).to eq(['updateFamily'])
  end
end
