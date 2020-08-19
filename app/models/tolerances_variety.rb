# frozen_string_literal: true

# Relation table for Tolerances and Varieties
class TolerancesVariety < ApplicationRecord
  belongs_to :tolerance
  belongs_to :variety
end
