# frozen_string_literal: true

class UploadPolicy < ApplicationPolicy
  def show?
    user.can_write?
  end

  def index?
    user.can_write?
  end
end
