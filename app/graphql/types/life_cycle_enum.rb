# frozen_string_literal: true

module Types
  # A reuseable enumerator for life cycle values
  class LifeCycleEnum < Types::BaseEnum
    graphql_name 'LifeCycleValue'
    description 'Describes how long a plant takes to complete their entire life cycle'
    value 'ANNUAL',
          value: 'annual',
          description: 'Plants perform their entire life cycle within a single growing season.'
    value 'PERENNIAL',
          value: 'perennial',
          description: 'Plants persist for many growing seasons.'
    value 'BIENNIAL',
          value: 'biennial',
          description: 'Plants require two years to complete their life cycle.'
  end
end
