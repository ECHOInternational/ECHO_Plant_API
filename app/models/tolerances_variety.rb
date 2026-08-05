# frozen_string_literal: true

# Relation table for Tolerances and Varieties
class TolerancesVariety < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :tolerance
  belongs_to :variety

  versioned_under_root { ['Variety', variety_id] }
end
