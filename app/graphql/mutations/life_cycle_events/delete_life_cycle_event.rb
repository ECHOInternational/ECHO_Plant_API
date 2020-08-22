# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Deletes a life cycle event
    class DeleteLifeCycleEvent < BaseMutation
      argument :life_cycle_event_id, ID,
               description: 'The life cycle event to be deleted',
               required: true,
               loads: Types::LifeCycleEventType

      field :life_cycle_event_id, ID, null: true
      field :errors, [Types::MutationError], null: false

      def authorized?(life_cycle_event:, **_attributes)
        specimen = life_cycle_event.specimen
        authorize specimen, :update?
      end

      def resolve(life_cycle_event:, **_attributes)
        id = PlantApiSchema.id_from_object(life_cycle_event, life_cycle_event.class, {})
        life_cycle_event.destroy
        errors = errors_from_active_record life_cycle_event.errors
        {
          life_cycle_event_id: life_cycle_event.destroyed? ? id : nil,
          errors: errors
        }
      end
    end
  end
end
