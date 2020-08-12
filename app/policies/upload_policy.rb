# frozen_string_literal: true

# Defines the unique secuirty policy for Upload objects
class UploadPolicy < ApplicationPolicy
  def show?
    user.can_write?
  end

  def index?
    user.can_write?
  end
end
