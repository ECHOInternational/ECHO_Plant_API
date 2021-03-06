# frozen_string_literal: true

# Ensures that a provided value matches the pattern of a UUID
class UuidValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    return if uuid_regex.match?(value)

    record.errors[attribute] << (options[:message] || 'is not a valid UUID')
  end
end
