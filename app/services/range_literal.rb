# frozen_string_literal: true

# Serializes an ActiveRecord Range attribute (backed by a Postgres int4range
# or numrange column) back into the bracket-literal string format the write
# side (Mutations::Concerns::RangeLiteralValidation::RANGE_LITERAL) accepts,
# e.g. "[10,20]", "[10,]", "[,100]". Symmetric with writes: what an editor
# typed on create/update is what they see again on read.
#
# Before this existed, the 7 range fields on PlantType/VarietyType rendered
# through graphql-ruby's default String coercion, i.e. Ruby's Range#to_s --
# "5.5..7.0", "600...1201", "0...Infinity" in production. Writes accepted
# bracket literals; reads emitted Ruby Range syntax. The admin SPA's range
# parser (and the documented write format) only understands bracket
# literals, so every existing value rendered as a blank input.
#
# This module is stateless -- all methods are module functions.
module RangeLiteral
  module_function

  # range - a Ruby Range as ActiveRecord's PostgreSQL::OID::Range casts it
  # (nil endpoints from an unbounded side are represented as
  # Float::INFINITY / -Float::INFINITY, never literal nil, but nil is
  # tolerated defensively). Returns nil for a nil range, otherwise a bracket
  # literal string.
  def serialize(range)
    return nil if range.nil?

    lower = range.begin
    upper = range.end
    exclude_end = range.exclude_end?
    upper_unbounded = unbounded?(upper)

    # Postgres canonicalizes discrete ranges (int4range) to an inclusive
    # lower / exclusive upper bound -- an editor who wrote the inclusive
    # literal "[500,2000]" gets back the Ruby Range 500...2001 once the row
    # round-trips through the database. Numeric ranges (numrange) are
    # continuous, so Postgres stores exactly the inclusivity it was given
    # and this branch never fires for them.
    if integer_range?(lower, upper) && !upper_unbounded && exclude_end
      upper -= 1
      exclude_end = false
    end

    # An unbounded upper bound always renders as an empty side with a
    # closing "]" ("[10,]"), matching the literal the write side expects for
    # "no upper limit" -- never "[10,)", which would read as a real
    # (if oddly punctuated) exclusive bound rather than "unset".
    upper_bracket = upper_unbounded || !exclude_end ? ']' : ')'

    "[#{format_bound(lower)},#{format_bound(upper)}#{upper_bracket}"
  end

  # A Range's lower bound is always inclusive here: Ruby's Range class has
  # no way to represent an open lower bound (assigning a Postgres literal
  # with an open lower bound, e.g. "(5,10]", raises ArgumentError at cast
  # time), so the opening bracket is always "[".
  def unbounded?(bound)
    bound.nil? || (bound.respond_to?(:infinite?) && bound.infinite?)
  end
  private_class_method :unbounded?

  # int4range bounds cast to Integer; numrange bounds cast to BigDecimal.
  # Either bound being an Integer is enough to identify a discrete range,
  # since an unbounded side casts to Float::INFINITY regardless of subtype.
  def integer_range?(lower, upper)
    lower.is_a?(Integer) || upper.is_a?(Integer)
  end
  private_class_method :integer_range?

  def format_bound(bound)
    return '' if unbounded?(bound)
    return bound.to_s if bound.is_a?(Integer)
    return format_big_decimal(bound) if bound.is_a?(BigDecimal)

    bound.to_s
  end
  private_class_method :format_bound

  # BigDecimal#to_s defaults to scientific notation ("0.55e1" for 5.5), which
  # is not a valid range-literal bound. #to_s('F') gives fixed-point
  # notation instead. Formatting choice: a trailing ".0" is stripped, so a
  # whole-number bound like 7.0 renders as "7" (matching what an editor
  # would type for a whole number), while a fractional bound like 5.5 is
  # left untouched. The round-trip spec asserts this exact choice.
  def format_big_decimal(bound)
    str = bound.to_s('F')
    str.end_with?('.0') ? str.delete_suffix('.0') : str
  end
  private_class_method :format_big_decimal
end
