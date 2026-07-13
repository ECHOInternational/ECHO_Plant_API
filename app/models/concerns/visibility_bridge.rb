# frozen_string_literal: true

# Pure mapping functions between the legacy visibility integer enum and the new
# (publication_state, access_level, deleted_at) trio. Used by the dual-write
# callback, the backfill, and any read path that needs to derive one
# representation from the other.
#
# This module is stateless -- all methods are module functions.
module VisibilityBridge
  module_function

  # Maps a legacy visibility symbol to the new-model publication/access pair.
  # :deleted has no trio because deletion is expressed through deleted_at.
  TRIO_MAP = {
    private: { publication_state: 'published', access_level: 'organization' },
    public: { publication_state: 'published', access_level: 'public' },
    draft: { publication_state: 'draft', access_level: 'organization' }
  }.freeze

  # Returns { publication_state:, access_level: } for a given legacy visibility
  # symbol, or nil if the symbol is :deleted or unmapped.
  def trio_for(visibility_sym)
    TRIO_MAP[visibility_sym.to_sym]
  end

  # Derives the legacy visibility symbol from the new trio. Precedence:
  #   1. deleted_at present                    -> :deleted
  #   2. publication_state == 'draft'           -> :draft
  #   3. published + public access              -> :public
  #   4. everything else (incl. nil/nil legacy) -> :private
  def visibility_for(publication_state:, access_level:, deleted_at:)
    return :deleted    if deleted_at.present?
    return :draft      if publication_state == 'draft'
    return :public     if publication_state == 'published' && access_level == 'public'

    :private
  end
end
