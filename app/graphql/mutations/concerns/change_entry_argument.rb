# frozen_string_literal: true

module Mutations
  module Concerns
    # Shared decoding for the opaque ChangeEntry global id the restore-version
    # mutations accept. A malformed id, an id of another type, or a non-numeric
    # payload all mean the same thing to a caller: no such entry.
    module ChangeEntryArgument
      TYPE_NAME = 'ChangeEntry'
      NOT_FOUND_ERROR = {
        field: 'versionId',
        message: 'Change entry not found.',
        code: 404
      }.freeze

      def decode_change_entry_id(global_id)
        type_name, raw_id = GraphQL::Schema::UniqueWithinType.decode(global_id)
        return nil unless type_name == TYPE_NAME

        Integer(raw_id, 10)
      rescue ArgumentError, TypeError, GraphQL::ExecutionError
        nil
      end

      def change_entry_not_found_error
        NOT_FOUND_ERROR
      end
    end
  end
end
