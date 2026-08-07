# frozen_string_literal: true

module Types
  # Which view of a record to return. The second read lens in this schema;
  # `language:` setting Mobility.locale is the first.
  #
  # PUBLISHED is the default precisely so that anonymous and mobile callers,
  # which never send the argument, cannot receive draft content. That is the
  # leak-prevention mechanism and it requires nobody to remember anything.
  class PerspectiveEnum < Types::BaseEnum
    graphql_name 'Perspective'
    value 'PUBLISHED', 'The published record.', value: :published
    value 'DRAFT', 'The record with staged changes applied. Requires edit permission.', value: :draft
  end
end
