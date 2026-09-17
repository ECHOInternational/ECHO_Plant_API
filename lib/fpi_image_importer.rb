# frozen_string_literal: true

require 'aws-sdk-s3'
require Rails.root.join('lib/fpi_data_source')
require Rails.root.join('lib/fpi_image_manifest_entry')

# Writes the image rows for Food Plants International photographs and drawings
# (fpi-connector schema-delta items 14-16; decisions 36 and 57-59).
#
# The connector extracts each container, strips identifying metadata, uploads
# the bytes through createSourceUpload to <env prefix>fpi/<kind>s/<ROWID>-<hash>.<ext>
# in the images bucket, and delivers a manifest:
#
#   {"snapshot_id": "...", "images": [
#     {"kind": "photo" | "drawing", "rowid": 12, "plant_id": "<PLANT_ID>",
#      "key": "fpi/photos/12-0123456789ab.jpg", "content_type": "image/jpeg",
#      "sha256": "<64 hex>", "bytes": 68533, "name": "<scientific name> (photo 1)"}, ...]}
#
# For each entry the importer finds the FPI plant by source record id and
# writes the image as the source's service principal, private, with the source
# provenance columns and a deterministic id. Re-running is idempotent:
#
#   * same source record, same digest   -> unchanged (a missing Drawing tag is re-added)
#   * same source record, new digest    -> replaced: new key, curator-edited name,
#                                          description, attribution and tags carried over
#   * same source record, other plant   -> re-parented
#   * no plant for the PLANT_ID         -> missing_plant, nothing written
#   * object not in the bucket          -> not_uploaded, nothing written
#   * an FPI image absent from the manifest -> counted, never deleted (decision 11)
#
# Dry run by default: every entry is classified, nothing is written.
# rubocop:disable Metrics/ClassLength -- the six outcomes above each need their
# own write path and guard (create, replace carrying curator edits, re-parent,
# re-tag, and the two refusals); splitting them by line count would scatter the
# idempotency rules this class exists to keep together.
class FpiImageImporter
  DRAWING_ATTRIBUTE = 'Drawing'
  # Decision 57: permission to use every FPI image is granted; the written
  # documentation and the exact credit wording follow. Changing this constant
  # does not rewrite existing images.
  ATTRIBUTION = 'Food Plants International (Bruce French)'

  Totals = FpiImageImportTotals

  class InvalidManifest < StandardError; end

  def self.image_id(kind, rowid)
    FpiImageManifestEntry.new(kind: kind, rowid: rowid).image_id
  end

  def initialize(data_source:, run_id:, apply: false, bucket: nil, s3_client: nil)
    @data_source = data_source
    @run_id = run_id
    @apply = apply
    @bucket = bucket || Mutations::CreateSourceUpload.images_bucket
    @s3 = s3_client || Aws::S3::Client.new
    @principal = data_source.service_principal!
  end

  def run(manifest)
    entries = validate!(manifest)
    totals = Totals.empty
    PaperTrail.request(whodunnit: @principal.id, controller_info: { metadata: sync_metadata }) do
      Mobility.with_locale(:en) { entries.each { |entry| import(entry, totals) } }
    end
    totals.absent_from_manifest = FpiImageImporter.absent_count(@data_source, entries)
    totals
  end

  def self.absent_count(data_source, entries)
    Image.where(data_source_id: data_source.id).where.not(source_record_id: entries.map(&:source_record_id)).count
  end

  private

  def sync_metadata
    { origin: 'sync', data_source_id: @data_source.id, sync_run_id: @run_id }
  end

  def validate!(manifest)
    rows = manifest['images']
    raise InvalidManifest, 'manifest has no images list' unless rows.is_a?(Array)

    rows.each_with_index.map do |row, index|
      entry = FpiImageManifestEntry.from(row)
      problem = entry.problem(@data_source.source_system_key)
      raise InvalidManifest, "images[#{index}]: #{problem}" if problem

      entry
    end
  end

  def import(entry, totals)
    plant = Plant.unscoped.find_by(data_source_id: @data_source.id, source_record_id: entry.plant_id.to_s)
    return count(totals, :missing_plant, entry) unless plant

    existing = Image.find_by(data_source_id: @data_source.id, source_record_id: entry.source_record_id)
    return keep_image(existing, entry, plant, totals) if existing&.source_digest == entry.sha256

    write_image(existing, entry, plant, totals)
  rescue ActiveRecord::RecordInvalid => e
    count(totals, :invalid, entry, e.message)
  end

  def write_image(existing, entry, plant, totals)
    return count(totals, :not_uploaded, entry) unless uploaded?(entry)

    existing ? replace_image(existing, entry, plant) : create_image(entry, plant)
    count(totals, existing ? :replaced : :created, entry)
  end

  def keep_image(existing, entry, plant, totals)
    if existing.imageable_id != plant.id
      existing.update!(imageable: plant) if @apply
      return count(totals, :reparented, entry)
    end
    return count(totals, :unchanged, entry) unless entry.drawing? && !tagged?(existing)

    retag(existing) if @apply
    count(totals, :retagged, entry)
  end

  def create_image(entry, plant, carried = {})
    return unless @apply

    Image.create!(image_attributes(entry, plant, carried))
  end

  def image_attributes(entry, plant, carried)
    {
      id: entry.image_id, imageable: plant, s3_bucket: @bucket, s3_key: entry.key, visibility: :private,
      name: carried.fetch(:name, entry.name), description: carried[:description],
      attribution: carried.fetch(:attribution, ATTRIBUTION),
      created_by: @principal.email, owned_by: @principal.email,
      data_source_id: @data_source.id, source_record_id: entry.source_record_id, source_digest: entry.sha256,
      image_attribute_ids: (carried[:attribute_ids] || []) | (entry.drawing? ? [drawing_attribute.id] : [])
    }
  end

  # s3_key is read-only once persisted, so new bytes mean a new row under the
  # same id; what a curator may have edited travels across.
  def replace_image(existing, entry, plant)
    return unless @apply

    carried = { name: existing.name, description: existing.description, attribution: existing.attribution,
                attribute_ids: existing.image_attribute_ids }
    Image.transaction do
      existing.destroy!
      create_image(entry, plant, carried)
    end
  end

  def uploaded?(entry)
    head = @s3.head_object(bucket: @bucket, key: entry.key)
    entry.bytes.nil? || head.content_length == entry.bytes
  rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
    false
  end

  def tagged?(image)
    image.image_attribute_ids.include?(drawing_attribute.id)
  end

  def retag(image)
    ImageAttributesImage.find_or_create_by!(image_id: image.id, image_attribute_id: drawing_attribute.id)
  end

  # The attribute list is editable, so the tag is found by name at run time and
  # created when a curator has deleted it (schema-delta item 15).
  def drawing_attribute
    @drawing_attribute ||= ImageAttribute.i18n.find_by(name: DRAWING_ATTRIBUTE) ||
                           (@apply ? ImageAttribute.create!(name: DRAWING_ATTRIBUTE) : ImageAttribute.new(id: SecureRandom.uuid))
  end

  def count(totals, outcome, entry, message = nil)
    totals[outcome] += 1
    totals.details << "#{outcome}: #{entry.kind} #{entry.rowid}#{" (#{message})" if message}" unless %i[created unchanged].include?(outcome)
    outcome
  end
end
# rubocop:enable Metrics/ClassLength
