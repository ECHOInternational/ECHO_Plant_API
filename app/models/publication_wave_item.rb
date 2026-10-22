# frozen_string_literal: true

# One plant or image a publication wave changed, with the exact visibility
# columns before (prior) and after (applied). See PublicationWave.
#
# origin:  publish          written by the publisher
#          unpublish_sweep  an image the unpublisher made private because it
#                           became public after the wave started (a new
#                           upstream image on a wave plant, API-6)
# state:   pending   selected; the publisher has not reached it yet
#          applied   changed by the publisher
#          skipped   no longer eligible when the publisher reached it
#          missing   the row no longer exists
#          restored  put back to prior by the unpublisher (or swept)
#          drift     changed by someone else after the wave; left alone
#
# Deliberately NOT versioned, like RecordDraft: the items ARE the ledger, and
# versioning them would add about 20k version rows per wave. The opt-out
# overrides the inherited paper_trail_options (see record_draft.rb for why
# this is the only shape that works with PaperTrail 17).
class PublicationWaveItem < ApplicationRecord
  self.paper_trail_options = paper_trail_options.merge(unless: ->(_) { true })

  ITEM_TYPES = %w[Plant Image].freeze
  ORIGINS = %w[publish unpublish_sweep].freeze
  STATES = %w[pending applied skipped missing restored drift].freeze

  belongs_to :publication_wave, inverse_of: :items

  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :state, inclusion: { in: STATES }
  validates :item_id, :plant_id, presence: true

  # One pending plant item per id, in bulk (the publisher's first step).
  def self.insert_pending_plants!(wave, plant_ids)
    now = Time.current
    plant_ids.each_slice(1000) do |slice|
      insert_all!(slice.map do |id|
        { publication_wave_id: wave.id, item_type: 'Plant', item_id: id, plant_id: id, origin: 'publish',
          state: 'pending', created_at: now, updated_at: now }
      end)
    end
  end
end
