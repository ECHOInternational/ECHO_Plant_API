class Image < ApplicationRecord
  extend Mobility
  after_initialize :build_urls
  translates :name, :description
  validates :name, :owned_by, :created_by, presence: true
  validates :id, uniqueness: true, uuid: true, presence: true
  attribute :base_url, :string
  attr_readonly :s3_bucket, :s3_key # These should not change once the record has been created
  validates :s3_bucket, presence: true
  validates :s3_key, presence: true
  has_many :image_attributes_image, dependent: :destroy
  has_many :image_attributes, through: :image_attributes_image
  belongs_to :imageable, polymorphic: true, optional: false
  enum visibility: { private: 0, public: 1, draft: 2, deleted: 3 }, _prefix: :visibility

  # Raise an error when trying to update readonly fields
  def s3_key=(val)
    raise(ActiveRecord::ReadOnlyRecord, 's3_key is readonly') if persisted?

    super
  end

  def s3_bucket=(val)
    raise(ActiveRecord::ReadOnlyRecord, 's3_bucket is readonly') if persisted?

    super
  end

  private

  def build_urls
    self.base_url = "https://images.echocommunity.org/#{s3_key}"
  end
end
