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

# A third `namespace :families do` block, same reason as the second: keeps
# each task's body short enough to stay under Metrics/BlockLength without an
# exclusion.
namespace :families do
  desc <<~DESC
    Load the family seed banking metadata from issue #83.
    ENV:
      DRY_RUN '1' (default) reports only, '0' writes
      FILE    CSV path (default db/seeds/family_seed_banking.csv)
  DESC
  task load_seed_banking: :environment do
    require 'csv'

    path = ENV.fetch('FILE', 'db/seeds/family_seed_banking.csv')
    rows = CSV.read(path, headers: true).map(&:to_h)

    # Six family names from issue #83's first spreadsheet are COL synonyms,
    # so their guidance belongs on the accepted family. This map covers that
    # broader COL-synonym reality, not just what this spreadsheet happens to
    # exercise: only Chenopodiaceae also appears as a row in
    # family_seed_banking.csv (the second spreadsheet) -- the other five, and
    # Lycoperdiaceae (which has no COL target and is reported rather than
    # guessed at, alongside Pomaceae), never occur as rows here at all.
    redirects = {
      'Chenopodiaceae' => 'Amaranthaceae',
      'Cystoseiraceae' => 'Sargassaceae',
      'Exidiaceae' => 'Auriculariaceae',
      'Melanogastraceae' => 'Paxillaceae',
      'Nostochopsidaceae' => 'Hapalosiphonaceae',
      'Leuconostocaceae' => 'Lactobacillaceae'
    }

    report = FamilySeedBankingLoader.new(
      rows: rows, redirects: redirects, dry_run: ENV.fetch('DRY_RUN', '1') != '0'
    ).run
    puts report
  end
end
