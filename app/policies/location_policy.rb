# frozen_string_literal: true

# Defines the unique security policy for Location objects
class LocationPolicy < OwnedResourcePolicy
  # Locations have a soft delete, and the admin SPA uses it -- but the frozen
  # mobile app hard-deletes a location the user owns, with an ordinary
  # read/write token, during seed-trial sync
  # (echocommunity-app/app/store/SeedTrialReports/action.js:3736,
  # "mutation ($input: DeleteLocationInput!)"). That path is a compatibility
  # contract we cannot change: only the external developer can release the app,
  # and slowly.
  #
  # Before S7 the legacy owned_by == user.email rule authorized it. With that
  # rule gone the base destroy? collapses to superuser-only, so the sync would
  # start failing for every mobile user. spec/contracts/mobile_writes_contract
  # caught it.
  #
  # Deliberately NOT mapped onto the :soft_delete capability the way
  # SpecimenPolicy is. Specimens have no soft delete at all, so there an org
  # role's removal right has nowhere else to land. Locations do have one, and
  # the capability matrix reserves hard delete for types without a softer
  # option -- organization_authorization_matrix_spec asserts that a steward or
  # org_admin of a real organization cannot hard-delete a location.
  #
  # So this grants exactly what the legacy rule granted and nothing more: the
  # record's own owner. Post-backfill that is the owner's personal
  # organization, which is the faithful translation of `owned_by == user.email`.
  def destroy?
    return false unless user&.can_write?
    return true if user.super_admin?

    personal = user.personal_organization
    personal.present? && record.owner_organization_id == personal.id
  end
end
