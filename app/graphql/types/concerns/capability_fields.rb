# frozen_string_literal: true

module Types
  module Concerns
    # Mixes server-computed capability fields into a GraphQL object type.
    # Including types implement private helper methods to indicate which
    # Pundit policy action backs canDelete and canRestore. The policy
    # instance is memoized so resolving multiple capability fields on the
    # same object costs exactly one Pundit.policy call.
    #
    # Override delete_policy_method (default :destroy?) and
    # restore_policy_method (default nil = always false) in each type.
    module CapabilityFields
      extend ActiveSupport::Concern

      included do
        field :can_edit, GraphQL::Types::Boolean,
              null: false,
              description: 'True when the current user may update this record.'
        field :can_delete, GraphQL::Types::Boolean,
              null: false,
              description: 'True when the current user may delete this record.'
        field :can_restore, GraphQL::Types::Boolean,
              null: false,
              description: 'True when the current user may restore this soft-deleted record.'
      end

      def can_edit
        resolved_policy.update?
      end

      def can_delete
        resolved_policy.public_send(delete_policy_method)
      end

      def can_restore
        m = restore_policy_method
        return false if m.nil?

        resolved_policy.public_send(m)
      end

      private

      # Memoize the Pundit policy so multiple capability fields on one object
      # do not instantiate duplicate policy objects.
      def resolved_policy
        @resolved_policy ||= Pundit.policy(context[:current_user], @object)
      end

      # Overridable: the Pundit policy method to call for canDelete.
      def delete_policy_method
        :destroy?
      end

      # Overridable: the Pundit policy method to call for canRestore.
      # Return nil to always produce false (types that lack soft-delete).
      def restore_policy_method
        nil
      end
    end
  end
end
