# frozen_string_literal: true

require 'net/http'
require 'json'

# Reads accepted family-rank taxa from a Catalogue of Life release hosted on
# ChecklistBank.
#
# The pinned release is COL26.7 XR, ChecklistBank dataset 315834, issued
# 2026-07-17. GBIF migrated its own taxonomy to COL Extended Release after the
# GBIF Backbone was frozen at its 2023-08-28 build, which is why we source from
# here rather than GBIF.
class CatalogueOfLife
  HOST = 'https://api.checklistbank.org'
  # ChecklistBank refuses requests without a browser-like agent.
  USER_AGENT = 'Mozilla/5.0 (compatible; echo-plant-api/1.0; +https://echocommunity.org)'
  PAGE_SIZE = 1000
  DEFAULT_DATASET = '315834'
  DEFAULT_VERSION = 'COL26.7 XR'
  DEFAULT_SNAPSHOT = Date.new(2026, 7, 17)

  KINGDOMS = { 'P' => 'Plantae', 'F' => 'Fungi', 'C' => 'Chromista' }.freeze

  # COL publishes its own high-level grouping, which is more reliable than
  # deriving one from phylum and class: an attempt at that misfiled all 78
  # monocot families, because COL splits Magnoliopsida from Liliopsida while
  # both are angiosperms. Verified to cover 100 percent of the 4,596 families.
  PLANT_TYPE_BY_GROUP = {
    'angiosperms' => 'Angiosperms',
    'gymnosperms' => 'Gymnosperms',
    'pteridophytes' => 'Ferns & Fern Allies',
    'bryophytes' => 'Mosses, Liverworts & Hornworts',
    'algae' => 'Algae & Seaweed',
    'protists' => 'Protists',
    'ascomycetes' => 'Fungi',
    'basidiomycetes' => 'Fungi',
    'otherfungi' => 'Fungi',
    'fungi' => 'Fungi',
    'pseudofungi' => 'Fungi',
    'plants' => 'Other Plants',
    'eukaryotes' => 'Other'
  }.freeze

  def self.plant_type_for(group)
    PLANT_TYPE_BY_GROUP[group]
  end

  attr_reader :dataset

  def initialize(dataset: DEFAULT_DATASET)
    @dataset = dataset
  end

  def all_families
    KINGDOMS.flat_map { |id, name| families(kingdom_id: id, kingdom_name: name) }
  end

  def families(kingdom_id:, kingdom_name:)
    rows = []
    offset = 0
    loop do
      page = get_page(kingdom_id, offset)
      results = page['result'] || []
      break if results.empty?

      results.each { |record| rows << normalize_record(record, kingdom_name) }
      rows.compact!

      offset += PAGE_SIZE
      break if offset >= page['total'].to_i
    end
    rows
  end

  private

  def normalize_record(record, kingdom_name)
    usage = record['usage'] || {}
    name = usage.dig('name', 'scientificName')
    return nil if name.blank?

    {
      name: name,
      col_id: usage['id'],
      kingdom: kingdom_name,
      plant_type: self.class.plant_type_for(record['group'])
    }
  end

  def get_page(kingdom_id, offset)
    uri = URI("#{HOST}/dataset/#{dataset}/nameusage/search")
    uri.query = URI.encode_www_form(
      rank: 'family', status: 'accepted', TAXON_ID: kingdom_id,
      limit: PAGE_SIZE, offset: offset
    )
    JSON.parse(http_get(uri))
  end

  def http_get(uri)
    attempts = 0
    begin
      attempts += 1
      request = Net::HTTP::Get.new(uri, 'User-Agent' => USER_AGENT)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 90) do |http|
        http.request(request)
      end
      raise "COL responded #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    rescue StandardError
      # COL publishes no rate limit, so back off rather than hammer it.
      raise if attempts >= 3

      sleep(2**attempts)
      retry
    end
  end
end
