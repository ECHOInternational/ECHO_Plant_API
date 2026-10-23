# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Loaders::Batch do
  let(:context) { {} }
  let(:calls) { [] }

  def loader
    described_class.for(context, :things, default: []) do |ids|
      calls << ids
      ids.to_h { |id| [id, ["value #{id}"]] }
    end
  end

  it 'loads every id of one batch with one call, on the first value read' do
    lazies = %w[a b a].map { |id| loader.load(id) }
    expect(calls).to be_empty
    expect(lazies.map(&:value)).to eq [['value a'], ['value b'], ['value a']]
    expect(calls).to eq [%w[a b]]
  end

  it 'starts a new batch after one has run, so nothing is served stale' do
    loader.load('a').value
    loader.load('a').value
    expect(calls).to eq [%w[a], %w[a]]
  end

  it 'answers the default, never shared, for an id the block leaves out' do
    first = described_class.for(context, :empty, default: []) { {} }.load('x').value
    second = described_class.for(context, :empty, default: []) { {} }.load('y').value
    expect(first).to eq []
    expect(first).not_to be(second)
  end
end
