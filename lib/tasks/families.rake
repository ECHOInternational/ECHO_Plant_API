# frozen_string_literal: true

namespace :families do
  desc <<~DESC
    Seed the locked family list from the Catalogue of Life.
    ENV:
      DRY_RUN  '1' (default) reports without writing, '0' writes
      DATASET  ChecklistBank dataset key (default 315834, COL26.7 XR)
  DESC
  task seed: :environment do
    dry_run = ENV.fetch('DRY_RUN', '1') != '0'
    client = CatalogueOfLife.new(dataset: ENV.fetch('DATASET', CatalogueOfLife::DEFAULT_DATASET))

    puts "Fetching accepted families from Catalogue of Life dataset #{client.dataset}..."
    rows = client.all_families
    puts "Fetched #{rows.size} families."

    unmapped = rows.count { |r| r[:plant_type].nil? }
    puts "WARNING: #{unmapped} families have no plant type mapping." if unmapped.positive?

    by_kingdom = rows.group_by { |r| r[:kingdom] }.transform_values(&:size)
    by_kingdom.each { |k, n| puts format('  %<kingdom>-10s %<count>5d', kingdom: k, count: n) }

    existing = Family.pluck(:name).to_set(&:downcase)
    new_rows = rows.reject { |r| existing.include?(r[:name].downcase) }
    puts "\n#{new_rows.size} new, #{rows.size - new_rows.size} already present."

    if dry_run
      puts "\nDRY RUN. Re-run with DRY_RUN=0 to write."
      next
    end

    now = Time.current
    # translations is deliberately omitted here: an explicit {} looks inert but
    # is not. ActiveRecord::Type::Serialized#serialize collapses a hash equal to
    # the Mobility container coder's own "empty" value to nil rather than "{}",
    # so upsert_all would write a literal SQL NULL and trip the NOT NULL
    # constraint. Leaving the key out lets every INSERT fall through to the
    # column's own `DEFAULT '{}'`, and update_only never touches it either way.
    attributes = rows.map do |row|
      row.merge(
        status: 'accepted',
        classification_source: 'catalogue-of-life',
        classification_version: ENV.fetch('VERSION', CatalogueOfLife::DEFAULT_VERSION),
        snapshot_date: CatalogueOfLife::DEFAULT_SNAPSHOT,
        created_at: now,
        updated_at: now
      )
    end

    # upsert_all rather than the one-row-at-a-time style used by db/seeds.rb:
    # 4,596 rows through ActiveRecord with Mobility callbacks is needlessly
    # slow, and upserting is what makes a re-run idempotent.
    Family.importing do
      attributes.each_slice(500) do |slice|
        Family.upsert_all(slice, unique_by: 'index_families_on_lower_name',
                                 update_only: %i[col_id kingdom plant_type
                                                 classification_version snapshot_date])
      end
    end

    puts "Done. #{Family.count} families in the table."
    puts "\nData source: Catalogue of Life, CC-BY 4.0."
    puts 'Banki, O., Roskov, Y., Doring, M., Ower, G., et al. (2026). Catalogue of Life.'
  end
end
