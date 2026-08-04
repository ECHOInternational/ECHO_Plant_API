# frozen_string_literal: true

# Specimens are the one owned type with no soft delete.
class SpecimenPolicy < OwnedResourcePolicy
  # DeleteSpecimen is a hard delete, and SpecimenType#canDelete maps to
  # destroy?. The base destroy? has no organization branch at all -- its
  # org_granted argument is hardcoded false -- so once S7 removes the legacy
  # email rule it would collapse to superuser-only, and ordinary members would
  # lose the ability to remove their own specimens entirely. That is not the
  # intent: a specimen is a personal planting record, and the person keeping it
  # should be able to delete it.
  #
  # Mapped onto :soft_delete rather than a new :destroy capability, for two
  # reasons. Adding a destroy capability was considered and rejected -- soft
  # delete exists for a reason on the types that have it. And for those types
  # :soft_delete already means "the right to remove this from the working set";
  # specimens simply have no softer option, so it is the same right expressed
  # against the only mechanism they have.
  #
  # Deliberately NOT applied to Category, the other type whose canDelete maps
  # to destroy?: categories are a curated taxonomy the mobile navigation
  # depends on, and their writes are superuser-only by decision.
  def destroy?
    return false unless user&.can_write?

    legacy = user.super_admin? || record.owned_by == user.email
    org_granted = organization_capability?(:soft_delete)
    log_legacy_divergence(:destroy, legacy, org_granted)
    legacy || org_granted
  end
end
