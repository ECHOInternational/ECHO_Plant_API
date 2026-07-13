# frozen_string_literal: true

# Default Pundit policy base for objects that can be owned by users.
#
# Transition semantics (design.md section 7): effective authorization is the
# UNION of the legacy email-ownership rules and the new organization-
# membership rules. The legacy branches (owned_by email equality plus the
# trust-9/10 overrides) are scheduled for log-only demotion at cutover and
# removal in the cleanup phase; the organization branches are the target
# model. Nothing here may narrow what a pre-redesign token could do.
class OwnedResourcePolicy < ApplicationPolicy
  # Defines the parameters necessary to provide a protected scope
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      if user&.admin?
        scope.all
      elsif user
        org_ids = organization_ids_for_scope
        return legacy_scope if org_ids.empty?

        legacy_scope.or(scope.where(owner_organization_id: org_ids))
      else
        scope.where(visibility: :public)
      end
    end

    private

    def legacy_scope
      scope.where(visibility: :public).or(scope.where(owned_by: user.email))
    end

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
    if user
      return true if user.admin?
      return true if record.owned_by == user.email
      return true if organization_capability?(:read)
    end
    record.visibility_public?
  end

  def create?
    return false unless user

    user.can_write? || user.can_create_in_any_organization?
  end

  def update?
    return true if legacy_manage?

    organization_capability?(:update_any) ||
      (organization_capability?(:update_own) && user&.created_record?(record))
  end

  def destroy?
    return false unless user&.can_write?

    user.super_admin? || record.owned_by == user.email
  end

  # Soft deletion and restoration are steward-level capabilities in the new
  # model. The legacy owner/admin path is preserved for the transition: today
  # every owner may soft-delete (and restore) their own records and that must
  # not regress for existing clients.
  def soft_delete?
    legacy_manage? || organization_capability?(:soft_delete)
  end

  def restore?
    legacy_manage? || organization_capability?(:restore)
  end

  private

  # The pre-redesign update/soft-delete rule: a writer who owns the record by
  # email, or a trust-9 admin (D3 compatibility window).
  def legacy_manage?
    return false unless user&.can_write?

    user.admin? || record.owned_by == user.email
  end

  def organization_capability?(capability)
    return false unless user
    return false unless record.respond_to?(:owner_organization_id)
    return false if record.owner_organization_id.nil?

    user.organization_capability?(record.owner_organization_id, capability)
  end
end
