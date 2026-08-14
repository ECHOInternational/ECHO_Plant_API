# frozen_string_literal: true

# A Köppen-Geiger climate zone (D-017).
#
# The LIST is locked: rows may only be created or destroyed inside
# KoppenZone.importing, the same arrangement as Family. Everything ECHO adds on
# top - the translated name and description - is ordinary editable data.
#
# Three levels, self-parented:
#
#   group      5 rows   A B C D E
#   subgroup   8 rows   BS BW Cf Cs Cw Df Ds Dw
#   class     32 rows   the 30 published classes, plus BSn and BWn
#
# The subgroup level is not part of the published classification. It is kept
# because it carries 306 of ECHOcommunity's 512 existing assignments: a plant
# recorded as `Cf` is stating what is known without asserting a
# summer-temperature class, and deciding whether it means Cfa, Cfb or Cfc is an
# agronomic judgement rather than a lookup. `authoritative` marks the 30
# published classes so that distinction stays legible instead of being
# flattened away.
#
# BSn and BWn are kept too. They were first taken for ECHO inventions; `n` is a
# recognised third letter meaning frequent fog (Lima, Walvis Bay), absent from
# the Beck 2018 map only because rasters do not resolve fog.
#
# The natural key is `code`. Codes are defined by the classification and do not
# change; the names ECHO puts on them do.
class KoppenZone < ApplicationRecord
  # Raised when something tries to add to or remove from the locked list.
  class ImmutableListError < StandardError; end

  IMPORT_FLAG = 'koppen_zones.import_mode'

  LEVELS = %w[group subgroup class].freeze

  extend Mobility
  translates :name, :description

  # Registered before the associations so the immutability guard fires first -
  # has_many ... dependent: registers its own before_destroy at the point it is
  # declared. See Family for the incident that established this ordering.
  before_create :assert_importing!
  before_destroy :assert_importing!

  belongs_to :parent, class_name: 'KoppenZone', optional: true
  has_many :children, class_name: 'KoppenZone', foreign_key: :parent_id,
                      inverse_of: :parent, dependent: :restrict_with_error

  validates :code, :level, :classification_source, :classification_version,
            :snapshot_date, presence: true
  validates :level, inclusion: { in: LEVELS }
  validate :parent_must_not_be_self

  scope :groups, -> { where(level: 'group') }
  scope :subgroups, -> { where(level: 'subgroup') }
  scope :classes, -> { where(level: 'class') }
  scope :authoritative, -> { where(authoritative: true) }
  scope :ordered, -> { order(:position, :code) }

  class << self
    # The only context in which the list itself may change. Mirrors
    # Family.importing, including the explicit reset in the ensure: a
    # transaction-local setting lives until the end of the ENCLOSING
    # transaction, so under transactional fixtures the list would otherwise
    # stay unlocked for the rest of any example that imported once, and the
    # trigger specs would pass without proving anything.
    def importing
      previous = Thread.current[:koppen_zone_importing]
      Thread.current[:koppen_zone_importing] = true
      transaction do
        connection.execute("SELECT set_config('#{IMPORT_FLAG}', 'on', true)")
        yield
      end
    ensure
      Thread.current[:koppen_zone_importing] = previous
      connection.execute("SELECT set_config('#{IMPORT_FLAG}', 'off', true)") if connection.transaction_open?
    end

    def importing?
      Thread.current[:koppen_zone_importing] == true
    end
  end

  # The chain up to the group, nearest first: Cfa -> Cf -> C.
  def ancestry
    node = parent
    chain = []
    while node
      chain << node
      node = node.parent
    end
    chain
  end

  def translations_array
    translations.map do |language, attributes|
      { locale: language, name: attributes['name'],
        description: attributes['description'] }
    end
  end

  private

  def parent_must_not_be_self
    errors.add(:parent, 'cannot be the zone itself') if parent_id.present? && parent_id == id
  end

  def assert_importing!
    return if self.class.importing?

    raise ImmutableListError,
          'koppen_zones is a locked reference list; use KoppenZone.importing for imports'
  end
end
