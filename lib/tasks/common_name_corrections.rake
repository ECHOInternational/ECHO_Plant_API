# frozen_string_literal: true

require Rails.root.join('lib/common_name_corrections')

# Thin wrapper; the six corrections and the reasoning for each live in
# lib/common_name_corrections.rb.
#
#   bin/rails plants:correct_common_names              # dry run, changes nothing
#   APPLY=true bin/rails plants:correct_common_names   # write
namespace :plants do
  desc 'Correct six mistagged/duplicate common names (dry run unless APPLY=true)'
  task correct_common_names: :environment do
    apply = ENV['APPLY'] == 'true'
    puts apply ? 'APPLYING corrections' : 'DRY RUN — nothing will be written'

    result = CommonNameCorrections.new(apply: apply).run
    result.lines.each { |line| puts "  #{line}" }

    puts format("\n%<d>d deleted, %<r>d retagged, %<g>d already gone, " \
                '%<c>d collided (deleted instead), %<m>d plants not found',
                d: result.deleted, r: result.retagged, g: result.already_gone,
                c: result.would_collide, m: result.missing_plants)

    if result.errors.any?
      puts "\nerrors:"
      result.errors.each { |e| puts "  #{e}" }
    end

    puts "\nRe-run with APPLY=true to write." unless apply
  end
end
