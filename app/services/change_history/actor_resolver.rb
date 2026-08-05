# frozen_string_literal: true

module ChangeHistory
  # Resolves the acting identity behind a version row.
  #
  # Resolution order (design spec): metadata.principal_id, then whodunnit read
  # as a principal id (what the sync writer stores), then whodunnit read as an
  # external JWT uid, then a fallback label.
  #
  # One instance is created per GraphQL request and memoizes every lookup, so a
  # page of entries written by the same person costs a single query. Raw uids
  # are never surfaced as a label: they identify a person without naming one.
  class ActorResolver
    UNKNOWN_LABEL = 'Unknown user'
    SYNC_LABEL = 'Automated import'
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    def initialize
      @by_id = {}
      @by_uid = {}
    end

    def principal_for(version)
      principal_id = metadata(version)['principal_id']
      return find_by_id(principal_id) if principal_id.present?

      whodunnit = version.whodunnit
      return nil if whodunnit.blank?

      find_by_id(whodunnit) || find_by_uid(whodunnit)
    end

    def label_for(version)
      principal = principal_for(version)
      return principal.display_name.presence || principal.email.presence || UNKNOWN_LABEL if principal

      metadata(version)['origin'] == 'sync' ? SYNC_LABEL : UNKNOWN_LABEL
    end

    private

    def metadata(version)
      version.metadata.is_a?(Hash) ? version.metadata : {}
    end

    # principals.id is a uuid column: handing it a JWT uid that is not a uuid
    # would raise a StatementInvalid rather than return nil.
    def find_by_id(value)
      return nil unless value.to_s.match?(UUID_FORMAT)

      @by_id.fetch(value) { @by_id[value] = Principal.find_by(id: value) }
    end

    def find_by_uid(value)
      @by_uid.fetch(value) { @by_uid[value] = Principal.find_by(external_uid: value) }
    end
  end
end
