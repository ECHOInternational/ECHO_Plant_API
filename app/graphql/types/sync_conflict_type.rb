# frozen_string_literal: true

module Types
  # Represents a detected sync conflict between an external data source and the
  # local database. Three payloads are stored: base (last accepted snapshot),
  # local (current local state), and incoming (what the source now reports).
  class SyncConflictType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    field :conflict_type,    String,                          null: false
    field :status,           String,                          null: false
    field :resolution,       String,                          null: true
    field :base_payload,     String,                          null: true,
                                                              description: 'JSON-encoded base payload'
    field :local_payload,    String,                          null: true,
                                                              description: 'JSON-encoded local payload'
    field :incoming_payload, String,                          null: true,
                                                              description: 'JSON-encoded incoming payload'
    field :sync_run_id,      String,                          null: true
    field :resolved_at,      GraphQL::Types::ISO8601DateTime, null: true
    field :created_at,       GraphQL::Types::ISO8601DateTime, null: false
    field :syncable,         Types::OwnedRecordUnion,         null: true
    field :data_source,      Types::DataSourceType,           null: false

    def base_payload
      JSON.generate(object.base_payload) if object.base_payload
    end

    def local_payload
      JSON.generate(object.local_payload) if object.local_payload
    end

    def incoming_payload
      JSON.generate(object.incoming_payload) if object.incoming_payload
    end
  end
end
