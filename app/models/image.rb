# frozen_string_literal: true

# Images can be related to any 'imageable' object
class Image < ApplicationRecord
  include VersionedUnderRoot

  extend Mobility
  after_initialize :build_urls
  translates :name, :description
  validates :name, :owned_by, :created_by, presence: true
  validates :id, uniqueness: true, uuid: true, presence: true
  attribute :base_url, :string
  # attr_readonly :s3_bucket, :s3_key # These should not change once the record has been created
  validates :s3_bucket, presence: true
  validates :s3_key, presence: true
  has_many :image_attributes_image, dependent: :destroy
  has_many :image_attributes, through: :image_attributes_image
  belongs_to :imageable, polymorphic: true, optional: false, touch: true
  enum :visibility, { private: 0, public: 1, draft: 2, deleted: 3 }, prefix: :visibility

  # Display order inside one imageable (FPI plan API-5): images.position,
  # 1-based. NULL only for a row written by an older release during a deploy;
  # it sorts last, which is where an appended image belongs. created_at and id
  # make the order total. Backfilled by lib/image_positions.rb.
  DISPLAY_ORDER = Arel.sql('images.position ASC NULLS LAST, images.created_at ASC, images.id ASC')
  scope :display_ordered, -> { reorder(DISPLAY_ORDER) }

  before_create :append_position
  before_update :append_position_on_reparent

  # Images hang off many parents; only plant and variety images belong in a
  # record history timeline. Read the columns rather than the association so
  # this still works in after_destroy.
  versioned_under_root do
    %w[Plant Variety].include?(imageable_type) ? [imageable_type, imageable_id] : nil
  end

  # Raise an error when trying to update readonly fields
  def s3_key=(val)
    raise(ActiveRecord::ReadOnlyRecord, 's3_key is readonly') if persisted?

    super
  end

  def s3_bucket=(val)
    raise(ActiveRecord::ReadOnlyRecord, 's3_bucket is readonly') if persisted?

    super
  end

  # One entry per stored locale. Both fields are nullable on the GraphQL side,
  # so a locale holding only a name or only a description is returned as is.
  def translations_array
    translations.map do |language, attributes|
      { locale: language, name: attributes['name'], description: attributes['description'] }
    end
  end

  private

  # A new image goes after the current last image of its parent.
  def append_position
    self.position ||= next_position
  end

  # Re-parented images go to the end of their new parent, unless the caller
  # set a position in the same write.
  def append_position_on_reparent
    return unless (imageable_id_changed? || imageable_type_changed?) && !position_changed?

    self.position = next_position
  end

  def next_position
    return nil if imageable_type.blank? || imageable_id.blank?

    (Image.where(imageable_type: imageable_type, imageable_id: imageable_id).maximum(:position) || 0) + 1
  end

  def build_urls
    self.base_url = "https://images.echocommunity.org/#{s3_key}"
  end
end
