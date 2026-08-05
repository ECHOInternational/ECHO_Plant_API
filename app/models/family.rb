# frozen_string_literal: true

# A botanical, fungal or algal family, sourced from the Catalogue of Life.
#
# The LIST is locked: rows may only be created or destroyed by the importer,
# inside Family.importing. Everything ECHO adds on top (the translated
# description and the seed banking metadata) is ordinary editable data, gated
# at plant trust level 9 by FamilyPolicy.
#
# The natural key is `name`, not `col_id`. COL identifiers are documented as
# unstable and are forced to change whenever a name flips between accepted and
# synonym, which is exactly what happens when a family is merged. Family names
# do not change; their taxonomic status does.
class Family < ApplicationRecord
  # Raised when something tries to add to or remove from the locked list.
  class ImmutableListError < StandardError; end

  IMPORT_FLAG = 'families.import_mode'

  STORAGE_PHYSIOLOGIES = %w[orthodox recalcitrant intermediate variable mixed unknown].freeze
  SEED_LONGEVITIES = %w[low low_medium medium medium_high high].freeze
  STATUSES = %w[accepted superseded].freeze

  extend Mobility
  translates :description, :seed_banking_notes

  # Registered before the associations below so the immutability guard fires
  # first. has_many ... dependent: :nullify registers its own before_destroy
  # callback at the point it is declared; if that ran before this one, a
  # destroy attempted outside Family.importing would try to null out
  # plants.family_id (added in a later task) before this guard ever got a
  # chance to raise ImmutableListError.
  before_create :assert_importing!
  before_destroy :assert_importing!

  belongs_to :superseded_by, class_name: 'Family', optional: true
  has_many :plants, dependent: :nullify

  validates :name, :kingdom, :classification_source, :classification_version,
            :snapshot_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :storage_physiology, inclusion: { in: STORAGE_PHYSIOLOGIES }, allow_nil: true
  validates :seed_longevity, inclusion: { in: SEED_LONGEVITIES }, allow_nil: true
  validates :seed_banking_rank, inclusion: { in: 1..5 }, allow_nil: true

  scope :accepted, -> { where(status: 'accepted') }
  scope :superseded, -> { where(status: 'superseded') }

  class << self
    # The only context in which the list itself may change. Sets a Postgres
    # setting that the families_locked_list trigger checks, and a thread-local
    # that the model callbacks check, then restores both.
    #
    # The explicit reset in the ensure is load-bearing, not tidiness. A
    # transaction-local setting lives until the end of the ENCLOSING
    # transaction, and a nested `transaction` block joins the outer one rather
    # than scoping it. Under transactional test fixtures the enclosing
    # transaction is the whole example, so without this reset the list would
    # stay unlocked for the remainder of any example that imported once, and
    # the trigger specs would pass without proving anything.
    def importing
      previous = Thread.current[:family_importing]
      Thread.current[:family_importing] = true
      transaction do
        connection.execute("SELECT set_config('#{IMPORT_FLAG}', 'on', true)")
        yield
      end
    ensure
      Thread.current[:family_importing] = previous
      # Outside a transaction the setting is already gone with the commit, and
      # a local set_config would warn; only reset when one is still open.
      connection.execute("SELECT set_config('#{IMPORT_FLAG}', 'off', true)") if connection.transaction_open?
    end

    def importing?
      Thread.current[:family_importing] == true
    end
  end

  private

  def assert_importing!
    return if self.class.importing?

    raise ImmutableListError,
          'families is a locked reference list; use Family.importing for imports'
  end
end
