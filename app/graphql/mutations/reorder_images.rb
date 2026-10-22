# frozen_string_literal: true

module Mutations
  # Sets the display order of a record's images (FPI plan API-7).
  #
  # The listed images take positions 1..n in the given order; images of the
  # record that are not listed follow them in their current display order, so
  # a client may send only the images it shows. Every listed id must be an
  # image of this record and appear once; otherwise nothing changes and the
  # payload carries the error. Positions are display metadata: they are written
  # in one statement without PaperTrail versions, and the record is touched so
  # updatedSince readers see the change.
  class ReorderImages < BaseMutation
    argument :object_id, ID,
             description: 'The record whose images are reordered (a plant, variety, specimen, location, category or life-cycle event).',
             required: true
    argument :image_ids, [ID],
             description: 'The images in their new display order. Unlisted images of the record follow them.',
             required: true

    field :images, [Types::ImageType],
          description: "The record's images in their new display order, as the caller may see them.",
          null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(object_id:, **_attributes)
      authorize PlantApiSchema.object_from_id(object_id, {}), :update?
    end

    def resolve(object_id:, image_ids:)
      imageable = PlantApiSchema.object_from_id(object_id, {})
      current = imageable.images.reorder(Image::DISPLAY_ORDER).pluck(:id)
      listed, errors = decode_listed(image_ids, current)
      return { images: nil, errors: errors } if errors.any?

      renumber(imageable, listed + (current - listed))
      { images: Pundit.policy_scope(context[:current_user], imageable.images).display_ordered.to_a, errors: [] }
    end

    private

    def decode_listed(image_ids, current)
      errors = []
      listed = image_ids.map do |gid|
        uuid = decode(gid)
        errors << error(gid, 404, "image #{gid} is not an image of this record.") unless current.include?(uuid)
        uuid
      end
      listed.tally.each do |uuid, n|
        errors << error(image_ids[listed.index(uuid)], 400, 'image listed more than once.') if n > 1
      end
      [listed, errors]
    end

    def decode(gid)
      _type, uuid = GraphQL::Schema::UniqueWithinType.decode(gid)
      uuid
    rescue ArgumentError, GraphQL::ExecutionError
      nil
    end

    def error(value, code, message)
      { field: 'imageIds', value: value, code: code, message: message }
    end

    def renumber(imageable, ordered_ids)
      return if ordered_ids.empty?

      cases = ordered_ids.each_with_index.map do |id, i|
        ActiveRecord::Base.sanitize_sql(['WHEN ? THEN ?', id, i + 1])
      end
      Image.transaction do
        Image.where(id: ordered_ids).update_all("position = CASE id #{cases.join(' ')} END")
        imageable.touch
      end
    end
  end
end
