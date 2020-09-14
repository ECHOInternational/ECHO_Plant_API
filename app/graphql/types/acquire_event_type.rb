# frozen_string_literal: true

module Types
  # Defines fields for a Acquire event
  class AcquireEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Creates a Acquire Life Cycle Event attached to the specified specimen'

    field :condition, Types::ConditionEnum,
          description: 'Describes the quality or condition of germplasm on receipt - good,fair,poor',
          null: false

    field :accession, String,
          description: 'Accession is a group of related plant material from a single species which is collected at one time from a specific location',
          null: true

    field :source, String,
          description: 'Where did the germplasm come from (ECHO Florida,ECHO Asia,ECHO Tanzania,Other',
          null: false

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
