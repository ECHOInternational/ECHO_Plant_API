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
    report = FamilySeeder.new(client: client, version: ENV.fetch('VERSION', CatalogueOfLife::DEFAULT_VERSION),
                              dry_run: dry_run).run
    puts report

    next if dry_run

    puts "\nData source: Catalogue of Life, CC-BY 4.0."
    puts 'Banki, O., Roskov, Y., Doring, M., Ower, G., et al. (2026). Catalogue of Life.'
  end
end

# A second `namespace :families do` block (Rake merges same-named namespaces
# across a file) rather than one long block, so families:seed and
# families:reconcile each stay under Metrics/BlockLength without an
# exclusion.
namespace :families do
  desc <<~DESC
    Reconcile existing plants.family_names onto the families table.
    Writes a reviewable report and, unless DRY_RUN=0, changes nothing.
    ENV:
      DRY_RUN     '1' (default) reports only, '0' applies the confident matches
      MIN_CONFIDENCE  auto-apply floor for a GBIF spelling fix (default 80)
  DESC
  task reconcile: :environment do
    dry_run = ENV.fetch('DRY_RUN', '1') != '0'
    floor = ENV.fetch('MIN_CONFIDENCE', '80').to_i

    report = FamilyReconciler.new(min_confidence: floor, dry_run: dry_run).run
    puts report
  end
end
