# frozen_string_literal: true

module Types
  # Defines fields for a Disease event
  class DiseaseEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Actions taken when disease is observed'

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
