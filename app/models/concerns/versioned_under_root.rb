# frozen_string_literal: true

# Stamps { root_type, root_id } into the metadata of every PaperTrail version a
# child row produces, so the aggregated history for a plant or variety can pick
# its children up with one indexed containment lookup (see the GIN index on
# versions.metadata).
#
# Why the stamp is merged in AFTER PaperTrail writes the row, instead of using
# the model-level `meta:` option:
#
#   paper_trail 17 builds a version's attributes in
#   PaperTrail::Events::Base#merge_metadata_into, which runs
#   merge_metadata_from_model_into(data) first (assigning each model `meta:`
#   entry into data) and then returns
#   data.merge(PaperTrail.request.controller_info || {}).
#
#   Both the controller (ApplicationController#info_for_paper_trail returns
#   { metadata: { origin:, principal_id: } }) and any model `meta:` option would
#   target the same `metadata` column, and the controller's hash wins outright.
#   A `meta: { metadata: -> { ... } }` lambda would therefore lose root_type and
#   root_id on every request that carries controller info, which is every API
#   write. Merging into the stored jsonb afterwards is the only shape that keeps
#   the controller's provenance AND the root reference.
#
# Cost: one extra SELECT plus one UPDATE per child version. Child writes are
# rare next to reads, and the alternative loses data.
module VersionedUnderRoot
  extend ActiveSupport::Concern

  class_methods do
    # Declares how this model finds its history root. The block is evaluated in
    # instance context and must return [root_type_string, root_id] or nil.
    def versioned_under_root(&)
      define_method(:paper_trail_root_ref, &)
      private :paper_trail_root_ref
    end
  end

  included do
    after_create  :stamp_paper_trail_root
    after_update  :stamp_paper_trail_root
    after_destroy :stamp_paper_trail_root
  end

  private

  # PaperTrail records the destroy version in a before_destroy callback and the
  # create/update versions in after_ callbacks registered on ApplicationRecord,
  # which is earlier than this concern's callbacks in every case. The row we
  # stamp therefore always exists by the time this runs.
  def stamp_paper_trail_root
    return unless PaperTrail.enabled? && PaperTrail.request.enabled?

    root_type, root_id = paper_trail_root_ref
    return if root_type.blank? || root_id.blank?

    version_id = latest_paper_trail_version_id
    return if version_id.nil?

    merge_root_into_version_metadata(version_id, root_type, root_id)
  end

  def latest_paper_trail_version_id
    PaperTrail::Version
      .where(item_type: self.class.base_class.name, item_id: id)
      .order(id: :desc)
      .limit(1)
      .pick(:id)
  end

  def merge_root_into_version_metadata(version_id, root_type, root_id)
    PaperTrail::Version.where(id: version_id).update_all(
      [
        "metadata = COALESCE(metadata, '{}'::jsonb) || CAST(? AS jsonb)",
        { root_type: root_type, root_id: root_id }.to_json
      ]
    )
  end
end
