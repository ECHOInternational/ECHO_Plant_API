# frozen_string_literal: true

require Rails.root.join('lib/ec_data_source')
require Rails.root.join('lib/ec_record_linker')

# Bootstrap for running SourceSynchronizer against ECHOcommunity.
#
#   bin/rails sync:bootstrap                       # create the DataSource (idempotent)
#   bin/rails sync:link_plants[tmp/uuids.json]     # dry run
#   APPLY=true bin/rails sync:link_plants[...]     # write
#
# The uuids file is {"uuids": ["<uuid>", ...]} — the plants ECHOcommunity
# actually holds. Only those are linked; see lib/ec_record_linker.rb.
namespace :sync do
  desc 'Create the ECHOcommunity DataSource (idempotent)'
  task bootstrap: :environment do
    org_id = ENV['ECHO_ORG_ID'].presence or
      abort 'ECHO_ORG_ID is required (the organization the data source belongs to)'
    org = Organization.find_by(id: org_id) or abort "no organization with id #{org_id}"

    ds = EcDataSource.find_or_create!(organization: org)
    puts "DataSource #{ds.persisted? ? 'ready' : 'FAILED'}: #{ds.name} (#{ds.source_system_key})"
    puts "  id:           #{ds.id}"
    puts "  organization: #{org.name}"
    puts "  principal:    #{ds.service_principal!.email}"
    puts "  governs #{EcDataSource::PLANT_ATTRIBUTES.size} plant attributes"
  end

  desc 'Link API plants to their ECHOcommunity originals and seed the merge base'
  task :link_plants, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails sync:link_plants[path/to/uuids.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    data_source = EcDataSource.existing or abort 'run sync:bootstrap first'
    uuids = JSON.parse(File.read(path))['uuids'] or abort "no 'uuids' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    baseline = EcRecordLinker.baseline_from_seed(EcDataSource::PLANT_ATTRIBUTES)

    puts "#{apply ? 'LINKING' : 'DRY RUN'} against #{uuids.size} ECHOcommunity plants"
    puts "  data source:      #{data_source.name} (#{data_source.id})"
    puts "  2020 baseline:    #{baseline.size} plants available as a merge base"
    puts

    result = EcRecordLinker.new(data_source: data_source, source_uuids: uuids.to_set,
                                baseline: baseline, apply: apply).link

    puts "  plants #{apply ? 'linked' : 'to link'}: #{result.linked}"
    puts "    base = the 2020 export:   #{result.based_on_seed}"
    puts "    base = current local:     #{result.based_on_local}"
    puts "  already linked, untouched:  #{result.already_linked}"
    puts "  not in ECHOcommunity:       #{result.not_in_source}"
    puts "  failed:                     #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'linking finished with failures' if result.failed.positive?
  end
end
