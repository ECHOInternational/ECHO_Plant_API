# frozen_string_literal: true

# Publication waves of the FPI plan (tasks API-11 to API-14). See
# docs/fpi-publication.md for the operator guide.
module PublicationWaves
  # Raised for every refusal an operator must read (bad key, digest
  # mismatch, wrong state). The rake tasks abort with its message.
  class Refused < StandardError; end

  module_function

  # The service principal every wave write is attributed to (PaperTrail
  # whodunnit), like DataSource#service_principal! for syncs. Its email is a
  # service address, never printed by the reports.
  def ops_principal!
    email = 'ops+publication@plant-api.echocommunity.org'
    Principal.find_or_create_by!(identity_issuer: 'ops', email: email) do |p|
      p.kind = 'service'
      p.external_uid = nil
      p.display_name = 'Publication waves (ops)'
    end
  rescue ActiveRecord::RecordNotUnique
    Principal.find_by!(identity_issuer: 'ops', email: email)
  end

  # The visibility columns a wave changes and restores, as stored in
  # publication_wave_items.prior / applied. deleted_at is included so a plant
  # deleted after the wave counts as drift instead of being restored.
  def snapshot(record)
    case record
    when Plant
      { 'visibility' => record.visibility_before_type_cast.to_i, 'publication_state' => record.publication_state,
        'access_level' => record.access_level, 'deleted_at' => record.deleted_at&.utc&.iso8601(6) }
    when Image
      { 'visibility' => record.visibility_before_type_cast.to_i }
    else
      raise ArgumentError, "no wave snapshot for #{record.class.name}"
    end
  end

  # Runs block with every version attributed to the ops principal and stamped
  # with the wave's provenance (PaperTrail.request, as the sync does; a
  # model-level meta: would be clobbered, see versioned_under_root.rb).
  def with_provenance(origin:, wave:, data_source:, &)
    PaperTrail.request(
      whodunnit: ops_principal!.id,
      controller_info: { metadata: { origin: origin, wave_id: wave&.id, wave_key: wave&.key,
                                     data_source_id: data_source.id } },
      &
    )
  end
end
