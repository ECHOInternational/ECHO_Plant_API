# frozen_string_literal: true

class LifeCycleEventPolicy < ApplicationPolicy
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
