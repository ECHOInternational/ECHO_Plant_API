# frozen_string_literal: true

module Types
  # One entry in a record history timeline. The underlying object is a
  # PaperTrail::Version; every presented value is computed by the ChangeHistory
  # services. Never node addressable (see PlantApiSchema::NODE_FORBIDDEN_TYPES):
  # entries are only reachable through an already authorized parent record.
  class ChangeEntryType < Types::BaseObject
    description 'One recorded change to a record or one of its child rows.'

    KNOWN_ORIGINS = %w[api sync backfill].freeze

    field :id, ID, null: false,
                   description: 'Opaque id for this entry. Pass it to restorePlantVersion or restoreVarietyVersion.'
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false,
                                                        description: 'When the change was recorded.'
    field :event, Types::ChangeEventEnum, null: false
    field :origin, Types::ChangeOriginEnum, null: false
    field :actor, Types::PrincipalType, null: true,
                                        description: 'The identity behind the change, when it can be resolved.'
    field :actor_label, String, null: false,
                                description: 'Always-present display label for the actor.'
    field :subject_type, Types::ChangeSubjectEnum, null: false
    field :subject_label, String, null: true,
                                  description: 'Name of the child row this entry is about, when it can be resolved.'
    field :changes, [Types::FieldChangeType], null: false
    field :restorable, Boolean, null: false,
                                description: 'True when this entry can be restored with a restore-version mutation.'

    def id
      GraphQL::Schema::UniqueWithinType.encode('ChangeEntry', object.id)
    end

    def event
      return 'restored' if metadata['restored_from_version_id'].present?

      case object.event
      when 'create' then 'created'
      when 'destroy' then 'deleted'
      else 'updated'
      end
    end

    # Rows written before provenance metadata existed carry no origin.
    def origin
      value = metadata['origin'].to_s
      KNOWN_ORIGINS.include?(value) ? value : 'api'
    end

    def actor
      actor_resolver.principal_for(object)
    end

    def actor_label
      actor_resolver.label_for(object)
    end

    def subject_type
      subject.subject_type
    end

    def subject_label
      subject.label
    end

    def changes
      ChangeHistory::DiffBuilder.new(object).call
    end

    # Restoring an entry means reifying the version that FOLLOWS it, so the
    # newest entry for a record has nothing to restore from. Child subjects are
    # out of scope for v1.
    def restorable
      return false unless subject.subject_type == ChangeHistory::Subject::RECORD

      newest = newest_version_id
      newest.present? && object.id < newest
    end

    private

    def metadata
      object.metadata.is_a?(Hash) ? object.metadata : {}
    end

    def subject
      @subject ||= ChangeHistory::Subject.new(object)
    end

    # One resolver per request keeps actor lookups to one query per distinct
    # identity across the whole page.
    def actor_resolver
      context[:change_history_actor_resolver] ||= ChangeHistory::ActorResolver.new
    end

    def newest_version_id
      cache = (context[:change_history_newest_version_id] ||= {})
      key = [object.item_type, object.item_id]
      cache.fetch(key) do
        cache[key] = ChangeHistory::Query.newest_version_id(object.item_type, object.item_id)
      end
    end
  end
end
