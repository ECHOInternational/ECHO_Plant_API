# frozen_string_literal: true

module Types
  # Defines fields for a Weather event
  class WeatherEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Notation of unique weather events affecting plants or planting'

    field :condition, Types::ConditionEnum,
          description: 'Describes the quality or condition of weather for plants or planting - good,fair,poor',
          null: true

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
