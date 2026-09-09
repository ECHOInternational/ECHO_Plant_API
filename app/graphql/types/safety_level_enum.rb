# frozen_string_literal: true

module Types
  # The recorded safety level of a plant's edible parts.
  class SafetyLevelEnum < Types::BaseEnum
    graphql_name 'SafetyLevel'
    description 'The safety warning recorded against a plant. NONE means no warning has been ' \
                'recorded; it is not an assertion that the plant is safe to eat.'
    value 'NONE',
          value: 'none',
          description: 'No warning recorded. Not an assertion of safety.'
    value 'CAUTION',
          value: 'caution',
          description: 'The source flags this plant for caution: some part, preparation or quantity ' \
                       'is known to be harmful.'
    value 'POISONOUS',
          value: 'poisonous',
          description: 'The source marks this plant, or one of its parts, as poisonous or toxic.'
  end
end
