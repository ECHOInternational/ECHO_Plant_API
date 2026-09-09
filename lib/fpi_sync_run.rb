# frozen_string_literal: true

require Rails.root.join('lib/fpi_data_source')
require Rails.root.join('lib/fpi_plant_feed')
require Rails.root.join('lib/fpi_run_outcomes')
require Rails.root.join('lib/fpi_run_predictor')
require Rails.root.join('lib/fpi_run_totals')

# One synchronisation run of an fpi-connector payload directory
# (fpi-connector schema-delta item 4; risks A6, D4, D6, E4).
#
# The directory holds payload-manifest.json, shard-NNN.json files and
# deletions.json, as written by `fpi payload`. The run:
#
#   1. preflight -- refuses to start unless no migration is pending, the
#      payload's attributes_version matches this code, every pinned category
#      exists, every managed key has a reader on Plant, and every file's
#      digest matches the manifest;
#   2. applies every shard through one FpiPlantFeed per shard (one
#      SourceSynchronizer instance each, all under the same run id), then the
#      deletions;
#   3. writes the per-record outcome file and a summary (FpiRunOutcomes);
#   4. is considered failed when any row errored or was invalid.
#
# Dry run by default: build every row (which exercises the strict feed
# contract on the whole payload) and send nothing.
class FpiSyncRun
  class PreflightFailed < StandardError; end

  # Decision 35: Edible Plant Type codes 2, 3, 6 -> categories that must exist.
  PINNED_CATEGORY_IDS = %w[
    265c782d-c9e0-4c7a-8ab1-af672572508c
    aa9c55cd-6cc1-4893-be94-ed3df91d1a59
    97f62354-166d-4b75-a85d-2ea493ae2e03
  ].freeze

  DEFAULT_CONFLICT_CAP = 500

  class CapExceeded < StandardError; end

  # options: out_dir (default tmp/fpi/<run_id>), conflict_cap (default DEFAULT_CONFLICT_CAP; nil disables)
  def initialize(data_source:, payload_dir:, run_id:, apply: false, **options)
    @data_source = data_source
    @payload_dir = Pathname(payload_dir)
    @run_id = run_id
    @apply = apply
    @out_dir = options[:out_dir] || Rails.root.join('tmp', 'fpi', run_id)
    @conflict_cap = options.fetch(:conflict_cap, DEFAULT_CONFLICT_CAP)
  end

  def manifest
    @manifest ||= JSON.parse(@payload_dir.join('payload-manifest.json').read)
  end

  # Everything that must hold before a single row is sent. Returns the facts
  # checked, raising PreflightFailed on the first failure.
  def preflight!
    facts = { pending_migrations: check_migrations!, attributes_version: check_version! }
    check_categories!
    FpiPlantFeed.ensure_readable!
    facts.merge(verify_files, principal: @data_source.service_principal!.email)
  end

  # Builds every row first (the strict feed contract over the whole payload),
  # predicts the run and enforces the conflict cap, then applies shard by
  # shard. The prediction is the dry run's report and the applied run's guard:
  # a systematic connector change that would open thousands of conflicts is
  # refused before a single row is written (risks D5, G1).
  def run
    preflight!
    totals = FpiRunTotals.new
    started_at = Time.current
    batches = build_batches(totals)
    totals.prediction = FpiRunPredictor.new(data_source: @data_source).predict(batches.flat_map(&:last))
    enforce_cap!(totals.prediction)
    batches.each { |feed, rows| totals.merge!(feed.run(rows, apply: @apply).report) }
    write_outcomes(totals, started_at) if @apply
    totals
  end

  def self.failed?(totals)
    totals.failed?
  end

  private

  # [[feed, rows], ...]: one feed (one synchronizer) per shard, then the deletions.
  def build_batches(totals)
    batches = manifest['shards'].map { |entry| build_batch(totals, entry['file'], :build) }
    batches << build_batch(totals, manifest['deletions']['file'], :build_deletions) if manifest['deletions']
    batches
  end

  def build_batch(totals, file, builder)
    feed = FpiPlantFeed.new(data_source: @data_source, run_id: @run_id)
    rows = feed.public_send(builder, JSON.parse(@payload_dir.join(file).read))
    totals.shards += 1 if builder == :build
    totals.rows += rows.size
    [feed, rows]
  end

  def enforce_cap!(prediction)
    return unless @apply && @conflict_cap && prediction.conflict > @conflict_cap

    raise CapExceeded, "#{prediction.conflict} conflicts predicted, over the cap of #{@conflict_cap}; nothing written. " \
                       'Review the dry run, then raise CONFLICT_CAP only for a change you expect.'
  end

  def write_outcomes(totals, started_at)
    FpiRunOutcomes.new(data_source: @data_source, run_id: @run_id, out_dir: @out_dir).write(totals, manifest, started_at)
  end

  def check_migrations!
    pending = pending_migrations
    raise PreflightFailed, "pending migrations: #{pending.join(', ')}" if pending.any?

    pending
  end

  def check_version!
    version = manifest['attributes_version']
    return version if version == FpiDataSource::PLANT_ATTRIBUTES_VERSION

    raise PreflightFailed, "payload attributes_version #{version} but this API expects #{FpiDataSource::PLANT_ATTRIBUTES_VERSION}"
  end

  def verify_files
    facts = { shards: manifest['shards'].map { |s| verify_digest!(s) } }
    facts[:deletions] = verify_digest!(manifest['deletions']) if manifest['deletions']
    facts
  end

  def check_categories!
    missing = PINNED_CATEGORY_IDS.reject { |id| Category.unscoped.exists?(id) }
    raise PreflightFailed, "pinned categories missing: #{missing.join(', ')}" if missing.any?
  end

  def verify_digest!(entry)
    path = @payload_dir.join(entry['file'])
    raise PreflightFailed, "#{entry['file']} is missing" unless path.exist?

    actual = Digest::SHA256.file(path).hexdigest
    raise PreflightFailed, "#{entry['file']}: sha256 #{actual[0, 12]} differs from the manifest's #{entry['sha256'][0, 12]}" unless actual == entry['sha256']

    { file: entry['file'], bytes: path.size, sha256: actual }
  end

  def pending_migrations
    context = ActiveRecord::Base.connection_pool.migration_context
    context.migrations.map { |m| m.version.to_s } - context.get_all_versions.map(&:to_s)
  end
end
