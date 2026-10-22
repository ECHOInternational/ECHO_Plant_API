# frozen_string_literal: true

# One publication wave of the FPI plan (tasks API-11 to API-13): a named,
# reversible step that makes a selected set of a data source's private plants
# (and their private images) public. Written only by
# PublicationWaves::Publisher and PublicationWaves::Unpublisher, which record
# every changed row in publication_wave_items.
#
# States:
#   applying      the publisher created the wave and is working through items
#   applied       every item was processed
#   unpublishing  the unpublisher is restoring items
#   unpublished   the wave was rolled back; its plants may join a later wave
class PublicationWave < ApplicationRecord
  KEY_FORMAT = /\A[a-z0-9-]{3,40}\z/
  SELECTORS = %w[quality remaining ids].freeze
  STATES = %w[applying applied unpublishing unpublished].freeze
  ACTIVE_STATES = %w[applying applied unpublishing].freeze

  belongs_to :data_source
  has_many :items, class_name: 'PublicationWaveItem', dependent: :restrict_with_exception, inverse_of: :publication_wave

  validates :key, presence: true, format: { with: KEY_FORMAT }, uniqueness: true
  validates :selector, inclusion: { in: SELECTORS }
  validates :state, inclusion: { in: STATES }
  validates :selection_digest, presence: true
  validate :notes_hold_no_email

  scope :active, -> { where(state: ACTIVE_STATES) }

  private

  # The ledger is read in public GitHub Actions logs (this is a public
  # repository), so it must never hold an email address.
  def notes_hold_no_email
    errors.add(:notes, "must not contain '@' (no email addresses in the wave ledger)") if notes.to_s.include?('@')
  end
end
