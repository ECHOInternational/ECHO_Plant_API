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
