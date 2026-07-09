# frozen_string_literal: true

# Defines the unique secuirty policy for Upload objects
class UploadPolicy < ApplicationPolicy
  def show?
    user&.can_write? || false
  end

  def index?
    user&.can_write? || false
  end
end
