# frozen_string_literal: true

# Policy to govern all LifecycleEvents
class LifeCycleEventPolicy < ApplicationPolicy
  # Delegates the update? method to the parent specimen
  def update?
    SpecimenPolicy.new(@user, @record.specimen).update?
  end
  # Defines the parameters necessary to provide a protected scope
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope.includes(:specimen)
    end

    def resolve
      return public_scope unless user
      return scope.all if user.super_admin?

      org_ids = user.readable_organization_ids
      return public_scope if org_ids.empty?

      public_scope.or(scope.where(specimens: { owner_organization_id: org_ids }))
    end

    private

    def public_scope
      scope.where(specimens: { visibility: :public })
    end
  end
end
