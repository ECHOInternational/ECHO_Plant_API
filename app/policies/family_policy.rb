# frozen_string_literal: true

# Security policy for Family objects.
#
# Families is a locked reference list sourced from the Catalogue of Life. The
# LIST is immutable through the API: create? and destroy? are deliberately not
# defined here, so they inherit ApplicationPolicy's false. That is the whole
# point, and it is why this does not subclass OwnedResourcePolicy, whose
# create? grants creation to any trust-2 writer.
#
# The METADATA that ECHO layers on top (description, seed banking fields) is
# editable at trust level 9. That is deliberately lower than the other lookup
# tables, which require 10: their lists are editable, so a low bar would let
# anyone fork the vocabulary. Here the vocabulary cannot be forked at all, so
# only the annotations are at stake. Trust 10 also currently has no members,
# which would make metadata uneditable by anyone.
class FamilyPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def update?
    user&.admin?
  end
end
