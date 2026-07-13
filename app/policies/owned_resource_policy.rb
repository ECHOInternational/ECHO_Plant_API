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
    org_granted = organization_capability?(:update_any) ||
                  (organization_capability?(:update_own) && user&.created_record?(record))
    legacy = legacy_manage?
    log_legacy_divergence(:update, legacy, org_granted)
    legacy || org_granted
  end

  def destroy?
    return false unless user&.can_write?

    legacy = user.super_admin? || record.owned_by == user.email
    log_legacy_divergence(:destroy, legacy, false)
    legacy
  end

  # Soft deletion and restoration are steward-level capabilities in the new
  # model. The legacy owner/admin path is preserved for the transition: today
  # every owner may soft-delete (and restore) their own records and that must
  # not regress for existing clients.
  def soft_delete?
    legacy = legacy_manage?
    org_granted = organization_capability?(:soft_delete)
    log_legacy_divergence(:soft_delete, legacy, org_granted)
    legacy || org_granted
  end

  def restore?
    legacy = legacy_manage?
    org_granted = organization_capability?(:restore)
    log_legacy_divergence(:restore, legacy, org_granted)
    legacy || org_granted
  end

  private

  # Rollout observability (runbook stage S6). When ORG_AUTHZ_CUTOVER=log_only,
  # emit a structured event whenever access is granted ONLY by a legacy branch
  # (email ownership or the trust-9/10 override) and would be DENIED once legacy
  # authorization is removed. A quiet window of zero such events is the evidence
  # gate for the S7 cleanup that drops the legacy branches. No PII is logged
  # (principal id + org id + action only), and logging never affects the
  # authorization outcome.
  def log_legacy_divergence(action, legacy_granted, org_granted)
    return unless ENV['ORG_AUTHZ_CUTOVER'] == 'log_only'
    return unless legacy_granted && !org_granted

    Rails.logger.info({
      event: 'authz.legacy_divergence',
      action: action,
      record_type: record.class.name,
      record_id: record.try(:id),
      principal_id: user&.principal&.id,
      owner_organization_id: record.try(:owner_organization_id),
      decision: 'granted_by_legacy_only'
    }.to_json)
  end

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
