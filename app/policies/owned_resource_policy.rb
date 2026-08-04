# frozen_string_literal: true

# Default Pundit policy base for objects that can be owned by users.
#
# Authorization is organization membership, full stop (design.md section 7).
#
# Until S7 this was the UNION of organization capabilities and a legacy layer:
# email equality against `owned_by`, plus a trust-9 global-admin override. That
# layer existed so a pre-redesign token kept working while the backfill placed
# every record into an organization. It is gone. What replaced each part:
#
#   owned_by == user.email   ->  every principal has a personal organization,
#                                and User#role_in grants org_admin on your own,
#                                so your own records stay fully manageable.
#   user.admin? (trust 9)    ->  organization roles. Trust >= 10 remains a
#                                system superuser and is unaffected.
#
# `owned_by` itself is untouched: it is part of the frozen mobile contract and
# is still written and returned. It simply no longer grants anything.
class OwnedResourcePolicy < ApplicationPolicy
  # Defines the parameters necessary to provide a protected scope
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      return scope.where(visibility: :public) unless user
      return scope.all if user.super_admin?

      org_ids = organization_ids_for_scope
      return scope.where(visibility: :public) if org_ids.empty?

      scope.where(visibility: :public).or(scope.where(owner_organization_id: org_ids))
    end

    private

    # Only meaningful when the scoped table carries the organization column
    # (Image does not; it has its own Scope).
    def organization_ids_for_scope
      klass = scope.is_a?(ActiveRecord::Relation) ? scope.klass : scope
      return [] unless klass.column_names.include?('owner_organization_id')

      user.readable_organization_ids
    end
  end

  def index?
    true
  end

  def show?
    return true if organization_capability?(:read)

    record.visibility_public?
  end

  def create?
    return false unless user

    user.can_write? || user.can_create_in_any_organization?
  end

  def update?
    organization_capability?(:update_any) ||
      (organization_capability?(:update_own) && user&.created_record?(record))
  end

  # Hard delete has no organization capability of its own and stays a superuser
  # act: the types that reach it have soft delete, which is the reversible
  # operation an organization role is granted. SpecimenPolicy overrides this,
  # because a specimen has no soft delete at all.
  def destroy?
    return false unless user&.can_write?

    user.super_admin?
  end

  def soft_delete?
    organization_capability?(:soft_delete)
  end

  def restore?
    organization_capability?(:restore)
  end

  private

  def organization_capability?(capability)
    return false unless user
    # The one global bypass in the target model (design.md D3). It lives here
    # rather than in each predicate because trust 10 used to reach update?,
    # soft_delete? and restore? through the legacy `user.admin?` branch (trust
    # > 8, which trust 10 also satisfies). Removing that layer without this
    # would have left a system superuser holding no org claims unable to edit
    # or restore anything -- exactly the recovery path a superuser exists for.
    return true if user.super_admin?
    return false unless record.respond_to?(:owner_organization_id)
    return false if record.owner_organization_id.nil?

    user.organization_capability?(record.owner_organization_id, capability)
  end
end
