# frozen_string_literal: true

# Defines the unique secuirty policy for Antinutrient objects
class AntinutrientPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    user&.super_admin?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end
end
