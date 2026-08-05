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
    resolver = FamilyResolver.new
    cache = {}

    applied = []
    review = []
    blank = []

    Plant.find_each do |plant|
      parsed = FamilyNameNormalizer.call(plant.family_names)
      if parsed[:kind] == :blank
        blank << plant
        next
      end

      results = parsed[:candidates].map { |c| cache[c] ||= resolver.resolve(c) }
      families = results.filter_map { |r| r[:family] }.uniq

      if families.size != 1 || results.any? { |r| r[:family].nil? }
        review << { plant: plant, results: results, reason: :unresolved_or_conflicting }
        next
      end

      confidences = results.filter_map { |r| r[:confidence] }
      if confidences.any? && confidences.min < floor
        review << { plant: plant, results: results, reason: :low_confidence,
                    family: families.first }
        next
      end

      applied << { plant: plant, family: families.first }
    end

    puts '=' * 68
    puts "RECONCILIATION REPORT - #{Plant.count} plants"
    puts '=' * 68
    puts format('  %<label>-46s %<count>5d', label: 'Would be applied', count: applied.size)
    puts format('  %<label>-46s %<count>5d', label: 'Requires a human decision', count: review.size)
    puts format('  %<label>-46s %<count>5d', label: 'Blank family_names, left null', count: blank.size)

    puts "\nEVERY RECORD REQUIRING A HUMAN DECISION"
    review.each do |row|
      puts "\n  plant : #{row[:plant].scientific_name}"
      puts "  raw   : #{row[:plant].family_names.inspect}"
      puts "  reason: #{row[:reason]}"
      row[:results].each do |r|
        puts "          -> #{r[:family]&.name || '(no match)'} via=#{r[:via]} conf=#{r[:confidence]}"
      end
    end

    puts "\nRESULTING FAMILY DISTRIBUTION"
    applied.group_by { |a| a[:family].name }.sort_by { |_, v| -v.size }.each do |name, rows|
      puts format('  %<count>4d  %<name>s', count: rows.size, name: name)
    end

    if dry_run
      puts "\nDRY RUN. Nothing was written. Re-run with DRY_RUN=0 to apply."
      next
    end

    applied.each { |row| row[:plant].update_columns(family_id: row[:family].id) }
    puts "\nApplied #{applied.size} family links. #{review.size} still need review."
  end
end
