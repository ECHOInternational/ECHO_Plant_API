# frozen_string_literal: true

module Types
  # Which part of the record a history entry is about.
  class ChangeSubjectEnum < Types::BaseEnum
    graphql_name 'ChangeSubject'
    description 'Which part of the record a history entry is about.'

    value 'RECORD', value: 'record', description: 'The plant or variety itself.'
    value 'COMMON_NAME', value: 'common_name'
    value 'CATEGORY', value: 'category'
    value 'TOLERANCE', value: 'tolerance'
    value 'GROWTH_HABIT', value: 'growth_habit'
    value 'ANTINUTRIENT', value: 'antinutrient'
    value 'IMAGE', value: 'image'
  end
end
