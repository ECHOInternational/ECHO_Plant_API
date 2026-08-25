# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Concerns::RangeLiteralValidation do
  let(:validator) { Class.new { include Mutations::Concerns::RangeLiteralValidation }.new }

  def errors_for(literal)
    validator.validate_range_literals(n_accumulation_range: literal)
  end

  describe 'literals RangeLiteral.serialize can emit -- must all be accepted' do
    [
      '[5,7]',
      '[5.5,7]',
      '[0,0]',
      '[-10,5]',
      '[10,]',   # unbounded upper
      '[,10]',   # unbounded lower
      '[,]',     # fully unbounded
      '[1,2)'    # finite exclusive upper (numrange, raw-data case)
    ].each do |literal|
      it "accepts #{literal.inspect}" do
        expect(errors_for(literal)).to eq([])
      end
    end
  end

  describe 'nil is a no-op (field left untouched)' do
    it 'produces no error' do
      expect(errors_for(nil)).to eq([])
    end
  end

  describe 'open lower bound ("(") -- rejected even though the regex used to allow it' do
    # A literal with a "(" opening bracket and a real (non-empty) lower value
    # cannot be represented by Ruby's Range class at all: assigning it to a
    # range attribute raises ActiveRecord::PostgreSQL's ArgumentError instead
    # of failing validation. This is the write-validation gap: the validator
    # must reject these up front so the mutation returns a payload 400
    # instead of crashing.
    ['(5,10]', '(5,)', '(-3,10]'].each do |literal|
      it "rejects #{literal.inspect} with a payload error (not a raised cast error)" do
        errors = errors_for(literal)
        expect(errors.length).to eq(1)
        expect(errors.first).to include(code: 400, field: 'nAccumulationRange')
      end
    end

    # An empty lower bound is unbounded regardless of which bracket
    # decorates it, so "(,10]" doesn't crash on cast -- but it's still
    # rejected: the serializer's own contract is that the opening bracket is
    # always "[", and accepting "(" here would let a form resubmit an
    # equivalent-but-different string that never round-trips back to itself.
    it 'rejects an empty-value open lower bound, e.g. "(,10]"' do
      errors = errors_for('(,10]')
      expect(errors.length).to eq(1)
      expect(errors.first[:code]).to eq(400)
    end
  end

  describe 'non-numeric bound content -- must still be rejected (Phase-4/#113 strictness)' do
    ['[abc,5]', '[5,abc]', '[,]x', 'not a range', '', '5,10', '[5;10]'].each do |literal|
      it "rejects #{literal.inspect}" do
        errors = errors_for(literal)
        expect(errors.length).to eq(1)
        expect(errors.first[:code]).to eq(400)
      end
    end
  end
end
