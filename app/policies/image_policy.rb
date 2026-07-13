# frozen_string_literal: true

# Defines the unique security policy for Image objects.
#
# Images are inherited children in the new model: rights flow through the
# imageable record's own policy (which itself unions legacy email ownership
# with organization capabilities). The image's own owned_by column remains a
# legacy uploader path honored via super (OwnedResourcePolicy) during the
# transition window.
class ImagePolicy < OwnedResourcePolicy
  def show?
    return true if user && imageable_manageable?

    super
  end

  def update?
    if user&.can_write?
      return true if imageable_manageable?
    end
    super
  end

  def destroy?
    if user&.can_write?
      return true if imageable_manageable?
    end
    super
  end

  def create?
    # Images cannot be created directly they must be created through an imageable object.
    false
  end

  # Images have no owner_organization_id column; list visibility follows the
  # legacy image rules plus "images attached to records my organizations own",
  # expressed per imageable table (life-cycle events resolve through their
  # specimen).
  class Scope < OwnedResourcePolicy::Scope
    DIRECT_IMAGEABLES = {
      'Plant' => 'plants', 'Variety' => 'varieties', 'Specimen' => 'specimens',
      'Location' => 'locations', 'Category' => 'categories'
    }.freeze

    def resolve
      if user&.admin?
        scope.all
      elsif user
        org_ids = user.readable_organization_ids
        return legacy_scope if org_ids.empty?

        legacy_scope.or(scope.where(org_imageable_condition, org_ids: org_ids))
      else
        scope.where(visibility: :public)
      end
    end

    private

    def legacy_scope
      scope.where(visibility: :public).or(scope.where(owned_by: user.email))
    end

    def org_imageable_condition
      direct = DIRECT_IMAGEABLES.map do |type, table|
        <<~SQL.squish
          (images.imageable_type = '#{type}' AND EXISTS (
            SELECT 1 FROM #{table} t
            WHERE t.id = images.imageable_id
              AND t.owner_organization_id IN (:org_ids)))
        SQL
      end
      via_event = <<~SQL.squish
        (images.imageable_type = 'LifeCycleEvent' AND EXISTS (
          SELECT 1 FROM life_cycle_events lce
          JOIN specimens s ON s.id = lce.specimen_id
          WHERE lce.id = images.imageable_id
            AND s.owner_organization_id IN (:org_ids)))
      SQL
      (direct + [via_event]).join(' OR ')
    end
  end

  private

  # True when the actor may manage (update) the record this image hangs off,
  # per that record's own policy. Covers the legacy imageable-owner email path
  # and the new organization capabilities in one place.
  def imageable_manageable?
    imageable = record.imageable
    return false if imageable.nil?

    Pundit.policy(user, imageable).update?
  end
end
