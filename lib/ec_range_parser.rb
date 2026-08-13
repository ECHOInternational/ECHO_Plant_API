# frozen_string_literal: true

# Parses the "min..max" range strings used by db/seeds/Plants.json and the
# ECHOcommunity migration export.
#
# The seed task used eval for this. Parsing avoids executing data, and keeps
# the behaviour in one place now that both the importer and its specs rely on
# it.
module EcRangeParser
  module_function

  # "25..32" -> 25..32, "5.0..7.0" -> 5.0..7.0, blank or malformed -> nil.
  def parse(str)
    return nil if str.blank?

    low, high = str.split('..', 2)
    return nil if high.nil?

    return Range.new(low.to_f, high.to_f) if low.include?('.') || high.include?('.')

    Range.new(low.to_i, high.to_i)
  end
end
