# frozen_string_literal: true

# Security policy for Category objects.
#
# Categories are a small, curated taxonomy that the mobile app's top-down
# navigation depends on, so they are treated like the other controlled lookup
# tables (Tolerance, GrowthHabit, Antinutrient, ImageAttribute): every write is
# restricted to system superusers (plant trust >= 10). This prevents ordinary
# writers from forking the shared taxonomy with near-duplicate categories.
#
# Reads are intentionally left to OwnedResourcePolicy so public categories stay
# readable by everyone, including anonymous clients. Associating a record WITH
# a category is authorized against the owning record's :update? in
# Mutations::Relations::UpdateRelationsBaseMutation, not here, so contributors
# can still categorize their plants.
class CategoryPolicy < OwnedResourcePolicy
  def create?
    user&.super_admin?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  def soft_delete?
    create?
  end

  def restore?
    create?
  end
end
