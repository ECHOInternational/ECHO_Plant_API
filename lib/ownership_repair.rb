# frozen_string_literal: true

require 'json'

# Repairs records that `rake ownership:preflight` reports as unreachable, so S7
# can ship without silently taking records away from people.
#
# WHY RECORDS BECOME UNREACHABLE
#
# The S3 backfill routed owners missing from the IdP identity export down its
# legacy-email path, creating principals with external_uid NULL. A JWT resolves
# a principal by (identity_issuer, external_uid), never by email, so nothing can
# ever resolve to one of those -- their personal organizations are unreachable
# by definition. Today the legacy email rule papers over this; S7 removes it.
#
# The export selects User.where.not(uid: nil), which is exactly how such owners
# get missed.
#
# THE AFFECTED IDENTITIES ARE NOT IN THIS REPOSITORY
#
# This repository is PUBLIC. The addresses being repaired, and the IdP uids they
# map to, are personal data and are supplied at runtime from a private source --
# the same treatment ownership:backfill gives its MAPPING file (rollout.md:
# "The export JSON contains PII ... never SCP to a laptop, email, or a public
# bucket"). Do not inline them here, in a spec, or in a commit message.
#
# Config shape (JSON), from a private s3:// object or a local path:
#
#   {
#     "link":  [ { "old_email": "...", "uid": "...", "email": "..." } ],
#     "purge": [ "..." ]
#   }
#
# CASE SENSITIVITY MATTERS
#
# IdP uids are mixed case. Postgres string comparison is case-sensitive and
# Principal.resolve! matches external_uid exactly, so a uid stored in the wrong
# case would resolve to nothing and recreate the very bug being fixed. Values
# are used exactly as supplied and must never be normalized.
#
# rubocop:disable Metrics/ModuleLength -- the operations performed on a repair
# config stay in one file on purpose. This deletes production records, and a
# reviewer should be able to follow exactly what happens to each entry without
# chasing it across files.
module OwnershipRepair
  ECHOCOMMUNITY_ISSUER = 'https://www.echocommunity.org'
  LEGACY_ISSUER = 'legacy-email'

  # Deletion order is forced by the associations: a Specimen destroys its own
  # life-cycle events and images, but Location has
  # `has_many :life_cycle_events, dependent: :restrict_with_error`, and Plant
  # restricts on both varieties and specimens. So specimens have to go first, or
  # their locations refuse to be deleted.
  #
  # Names, not constants: this file is required from a rake task at boot, before
  # the autoloader can resolve models. Resolved on use instead.
  PURGE_ORDER = %w[Specimen Location Variety Plant].freeze

  Config = Struct.new(:link, :purge, keyword_init: true)

  module_function

  def load_config(path)
    raw = JSON.parse(File.read(path))
    link = Array(raw['link']).map do |entry|
      %w[old_email uid email].each do |key|
        raise ArgumentError, "link entry missing '#{key}'" if entry[key].blank?
      end
      entry
    end
    Config.new(link: link, purge: Array(raw['purge']))
  rescue JSON::ParserError => e
    raise ArgumentError, "repair config is not valid JSON: #{e.message}"
  end

  def run!(config, dry_run: true)
    report = { link: [], purge: [], refused: [], linked: 0, purged: Hash.new(0) }
    config.link.each { |entry| apply_link!(entry, dry_run, report) }
    config.purge.each { |email| apply_purge!(email, dry_run, report) }
    report
  end

  def purge_models
    PURGE_ORDER.map(&:constantize)
  end

  # The unreachable personal organization for an address, or nil.
  def legacy_org_for(email)
    principal = Principal.find_by(identity_issuer: LEGACY_ISSUER, email: email, external_uid: nil)
    return nil if principal.nil?

    Organization.find_by(principal_id: principal.id, kind: 'personal')
  end

  def owned_counts(org)
    purge_models.index_with { |model| model.where(owner_organization_id: org.id).count }
  end

  # Adopting the uid keeps the existing personal organization, so every record it
  # owns becomes reachable without a single row being rewritten. Only when the
  # person has ALREADY signed in under their real address -- which created a
  # second principal and a second personal org -- do the records have to move.
  def link_plan(old_email, uid)
    legacy_org = legacy_org_for(old_email)
    return { action: :nothing_to_do } if legacy_org.nil?

    existing = Principal.find_by(identity_issuer: ECHOCOMMUNITY_ISSUER, external_uid: uid)
    if existing
      { action: :repoint, from_org: legacy_org, principal: existing,
        to_org: Organization.find_by(principal_id: existing.id, kind: 'personal') }
    else
      { action: :adopt, principal: Principal.find(legacy_org.principal_id), org: legacy_org }
    end
  end

  # Reports are written with a redacted label rather than the address, because
  # they are printed into CI logs that are public for this repository.
  def label(email)
    local, domain = email.to_s.split('@')
    "#{local.to_s[0, 2]}***@#{domain}"
  end

  def apply_link!(entry, dry_run, report)
    plan = link_plan(entry['old_email'], entry['uid'])
    case plan[:action]
    when :nothing_to_do
      report[:link] << "#{label(entry['old_email'])}: no unreachable personal organization (already repaired?)"
    when :adopt
      adopt!(entry, plan, dry_run, report)
    when :repoint
      repoint!(entry, plan, dry_run, report)
    end
  end

  def adopt!(entry, plan, dry_run, report)
    counts = owned_counts(plan[:org]).transform_keys(&:name)
    report[:link] << "#{label(entry['old_email'])} ADOPT uid onto principal " \
                     "#{plan[:principal].id}; becomes reachable: #{counts.inspect}"
    return if dry_run

    plan[:principal].update!(identity_issuer: ECHOCOMMUNITY_ISSUER,
                             external_uid: entry['uid'], email: entry['email'])
    report[:linked] += 1
  end

  def repoint!(entry, plan, dry_run, report)
    report[:link] << repoint_message(entry, plan)
    if plan[:to_org].nil?
      report[:refused] << "#{label(entry['old_email'])}: principal #{plan[:principal].id} has no personal organization"
      return
    end
    return if dry_run

    move_records!(plan[:from_org], plan[:to_org])
    report[:linked] += 1
  end

  def repoint_message(entry, plan)
    counts = owned_counts(plan[:from_org]).transform_keys(&:name)
    "#{label(entry['old_email'])} REPOINT to org #{plan[:to_org]&.id}; records to move: #{counts.inspect}"
  end

  def move_records!(from_org, to_org)
    purge_models.each do |model|
      model.where(owner_organization_id: from_org.id)
           .update_all(owner_organization_id: to_org.id)
    end
  end

  def apply_purge!(email, dry_run, report)
    org = legacy_org_for(email)
    if org.nil?
      report[:purge] << "#{label(email)}: no unreachable personal organization (already purged?)"
      return
    end

    report[:purge] << "#{label(email)}: #{owned_counts(org).transform_keys(&:name).inspect}"
    destroy_owned!(org, email, report) unless dry_run
  end

  # A restricted delete is reported, never forced: if someone else's event still
  # points at one of these locations, that is a fact to look at.
  def destroy_owned!(org, email, report)
    purge_models.each do |model|
      model.where(owner_organization_id: org.id).find_each { |r| destroy_one!(r, model, email, report) }
    end
  end

  def destroy_one!(record, model, email, report)
    if record.destroy
      report[:purged][model.name] += 1
    else
      report[:refused] << "#{model.name} #{record.id} (#{label(email)}): " \
                          "#{record.errors.full_messages.join('; ')}"
    end
  end
end
# rubocop:enable Metrics/ModuleLength
