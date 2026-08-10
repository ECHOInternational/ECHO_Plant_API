# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RangeLiteral, type: :service do
  describe '.serialize' do
    it 'returns nil for a nil range' do
      expect(described_class.serialize(nil)).to be_nil
    end

    context 'integer ranges (int4range)' do
      it 'decrements a finite exclusive upper bound to the inclusive equivalent' do
        # Postgres canonicalizes int4range to inclusive-lower/exclusive-upper,
        # so an editor's "[500,2000]" round-trips through the database as the
        # Ruby Range 500...2001.
        range = Range.new(500, 2001, true)
        expect(described_class.serialize(range)).to eq '[500,2000]'
      end

      it 'renders an unbounded upper as an empty side closed with ]' do
        range = Range.new(10, Float::INFINITY, true)
        expect(described_class.serialize(range)).to eq '[10,]'
      end

      it 'renders an unbounded lower as an empty side' do
        range = Range.new(-Float::INFINITY, 101, true)
        expect(described_class.serialize(range)).to eq '[,100]'
      end

      it 'renders a fully unbounded range as [,]' do
        range = Range.new(-Float::INFINITY, Float::INFINITY, true)
        expect(described_class.serialize(range)).to eq '[,]'
      end

      it 'handles negative bounds' do
        range = Range.new(-10, 5, true)
        expect(described_class.serialize(range)).to eq '[-10,4]'
      end
    end

    context 'numeric ranges (numrange)' do
      it 'formats inclusive BigDecimal bounds without scientific notation' do
        range = Range.new(BigDecimal('5.5'), BigDecimal('7.0'), false)
        expect(described_class.serialize(range)).to eq '[5.5,7]'
      end

      it 'strips a trailing .0 from a whole-number BigDecimal bound' do
        range = Range.new(BigDecimal('0.0'), BigDecimal('14.0'), false)
        expect(described_class.serialize(range)).to eq '[0,14]'
      end

      it 'does not touch a fractional bound that does not end in .0' do
        range = Range.new(BigDecimal('1.25'), BigDecimal('3.75'), false)
        expect(described_class.serialize(range)).to eq '[1.25,3.75]'
      end

      it 'preserves an exclusive upper bound (rare, only via raw data) as a paren form' do
        range = Range.new(BigDecimal('1.0'), BigDecimal('2.0'), true)
        expect(described_class.serialize(range)).to eq '[1,2)'
      end

      it 'renders a fully unbounded numeric range as [,]' do
        range = Range.new(-Float::INFINITY, Float::INFINITY, true)
        expect(described_class.serialize(range)).to eq '[,]'
      end

      it 'never emits BigDecimal engineering notation for the bounds' do
        # BigDecimal#inspect (and, on some bigdecimal versions, plain #to_s)
        # renders engineering notation, e.g. BigDecimal('5.5').inspect ==
        # "0.55e1". That is not a valid range-literal bound, so the
        # serializer must always go through #to_s('F'). Guard against a
        # future edit accidentally swapping back to plain #to_s/#inspect.
        expect(BigDecimal('5.5').inspect).to include 'e'
        range = Range.new(BigDecimal('5.5'), BigDecimal('7.0'), false)
        expect(described_class.serialize(range)).not_to include 'e'
      end
    end
  end
end
