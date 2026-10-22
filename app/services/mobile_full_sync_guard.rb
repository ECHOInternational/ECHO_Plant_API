# frozen_string_literal: true

# What the frozen mobile app may receive from the two plant lists it shows
# without any safety information (spec/contracts/mobile_full_sync_guard_contract_spec.rb).
#
# 1. The full sync. The app is the only client that calls plants() with
#    neither first: nor last:, and it stores every node it gets. An
#    unpaginated call therefore returns ONLY plants owned by an allow-listed
#    organization (MOBILE_FULL_SYNC_OWNER_ORG_IDS), public or private, for
#    every caller, super-admins included. The single exception is the
#    caller's own personal organization: the app's custom-plant sync is the
#    unpaginated plants(visibility: PRIVATE) call, and it deletes from the
#    device every custom plant the server stops returning.
#    Applied by Extensions::GuardedConnectionExtension, which is the only
#    place that still sees whether first:/last: were given.
#
# 2. The category browse. category(id) { plants(first: 15) } is paginated, so
#    (1) does not cover it. For anonymous callers it hides plants of
#    non-allow-listed organizations that carry a safety flag. The app's browse
#    is always anonymous (it sends its token in an "Authentication:" header
#    the API never reads); authenticated clients see the full set.
module MobileFullSyncGuard
  # safety_level and edibility_uncertain are both NOT NULL.
  SAFETY_FLAGGED_SQL = "plants.safety_level <> 'none' OR plants.edibility_uncertain"

  module_function

  def owner_organization_ids
    Rails.configuration.x.mobile_full_sync_owner_org_ids
  end

  # relation: the already policy-scoped Plant relation of an unpaginated call.
  def restrict_full_sync(relation, user)
    allowed = owner_organization_ids.dup
    personal_id = user&.personal_organization&.id
    allowed << personal_id if personal_id
    relation.where(plants: { owner_organization_id: allowed })
  end

  # relation: the already policy-scoped Plant relation of Category.plants.
  def restrict_category_browse(relation, user)
    return relation if user

    relation.where(plants: { owner_organization_id: owner_organization_ids })
            .or(relation.where.not(SAFETY_FLAGGED_SQL))
  end
end
