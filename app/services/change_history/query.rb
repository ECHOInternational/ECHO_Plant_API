# frozen_string_literal: true

module ChangeHistory
  # Builds the aggregated version feed for one root record (a Plant or a
  # Variety): the record's own versions plus every child version that
  # VersionedUnderRoot stamped with this root.
  class Query
    # A touch (Image belongs_to :imageable, touch: true) records a version with
    # no object_changes at all, because rails' touch does no dirty tracking.
    # Those rows carry nothing a reader can see, so they are filtered in SQL --
    # before pagination, so totalCount matches what is rendered.
    NO_CHANGE_NOISE_SQL = "NOT (versions.event = 'update' AND versions.object_changes IS NULL)"

    def self.newest_version_id(item_type, item_id)
      PaperTrail::Version.where(item_type: item_type, item_id: item_id).maximum(:id)
    end

    def initialize(record)
      @root_type = record.class.base_class.name
      @root_id = record.id
    end

    def relation
      own = PaperTrail::Version.where(item_type: @root_type, item_id: @root_id)
      children = PaperTrail::Version.where('versions.metadata @> CAST(? AS jsonb)', root_match_json)

      own.or(children).where(NO_CHANGE_NOISE_SQL).order(created_at: :desc, id: :desc)
    end

    private

    def root_match_json
      { root_type: @root_type, root_id: @root_id }.to_json
    end
  end
end
