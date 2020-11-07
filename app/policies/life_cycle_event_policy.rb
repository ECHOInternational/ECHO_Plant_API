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
      if user&.admin?
        scope.all
      elsif user
        scope.where(specimens: { visibility: :public }).or(scope.where(specimens: { owned_by: user.email }))
      else
        scope.where(specimens: { visibility: :public })
      end
    end
  end
end
