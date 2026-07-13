# frozen_string_literal: true

# Shared concern for the five independently-owned models (Plant, Variety,
# Specimen, Location, Category). Declares the new string enums, includes the
# VisibilityBridge, and installs the bidirectional dual-write callback that
# keeps the legacy visibility integer column in sync with the new
# publication_state / access_level / deleted_at trio.
#
# Inclusion is purely additive: no existing validations, associations, or enum
# definitions are changed. The new columns are nullable until the Phase B
# backfill runs, so no presence validations are added here.
module OrganizedResource
  extend ActiveSupport::Concern

  included do
    include VisibilityBridge

    # New string enums. Prefix avoids clashing with the existing integer
    # visibility enum and its generated methods.
    enum :publication_state,
         { draft: 'draft', published: 'published' },
         prefix: :publication

    enum :access_level,
         { organization: 'organization', public: 'public' },
         prefix: :access

    before_save :sync_visibility_columns
  end

  private

  # Resolves a visibility value (integer, string, or symbol) to a symbol.
  # Returns nil when the input cannot be resolved.
  def resolve_visibility_sym(val)
    return nil if val.nil?
    return val.to_sym if val.is_a?(Symbol)

    # Integer -> look up in the enum hash ({"private"=>0,...})
    if val.is_a?(Integer)
      key = self.class.visibilities.key(val)
      return key&.to_sym
    end

    # String: may be a name like "private" or a stringified integer like "0"
    str = val.to_s
    # Try as integer string first
    if str.match?(/\A\d+\z/)
      key = self.class.visibilities.key(str.to_i)
      return key&.to_sym
    end

    # Try as enum name
    str.to_sym if self.class.visibilities.key?(str)
  end

  # Bidirectional dual-write with deterministic precedence:
  #   (a) New-API path: any of publication_state/access_level/deleted_at
  #       changed -> recompute legacy visibility from the new trio.
  #   (b) Legacy-API path: visibility changed (and new columns did not) ->
  #       propagate to the trio. :deleted sets deleted_at without overwriting
  #       the trio (preserving pre-deletion state); non-deleted values set the
  #       trio and clear deleted_at.
  #   (c) Create path (legacy): visibility is set but the trio is nil ->
  #       populate the trio from the visibility value.
  def sync_visibility_columns
    new_api_changed = publication_state_changed? ||
                      access_level_changed?      ||
                      deleted_at_changed?

    if new_api_changed
      # Precedence (a): new trio is authoritative this save.
      derived = VisibilityBridge.visibility_for(
        publication_state: publication_state,
        access_level: access_level,
        deleted_at: deleted_at
      )
      self.visibility = self.class.visibilities[derived]
    elsif visibility_changed?
      # Precedence (b): legacy visibility is authoritative this save.
      new_vis_sym = resolve_visibility_sym(visibility)

      if new_vis_sym == :deleted
        # Preserve pre-deletion trio; capture it from the prior visibility if
        # the trio is currently nil (row created before this concern was active).
        if publication_state.nil? || access_level.nil?
          prior_sym = resolve_visibility_sym(visibility_was)
          if prior_sym && prior_sym != :deleted
            trio = VisibilityBridge.trio_for(prior_sym)
            if trio
              self.publication_state = trio[:publication_state]
              self.access_level      = trio[:access_level]
            end
          end
        end
        self.deleted_at ||= Time.current
      else
        # Restore or ordinary change: clear deletion and set trio.
        self.deleted_at              = nil
        self.deleted_by_principal_id = nil
        trio = VisibilityBridge.trio_for(new_vis_sym)
        if trio
          self.publication_state = trio[:publication_state]
          self.access_level      = trio[:access_level]
        end
      end
    elsif new_record? && !publication_state && !access_level
      # Precedence (c): create path -- populate trio from current visibility.
      vis_sym = resolve_visibility_sym(visibility)
      if vis_sym && vis_sym != :deleted
        trio = VisibilityBridge.trio_for(vis_sym)
        if trio
          self.publication_state = trio[:publication_state]
          self.access_level      = trio[:access_level]
        end
      end
    end
  end
end
