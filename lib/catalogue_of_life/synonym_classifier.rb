# frozen_string_literal: true

class CatalogueOfLife
  # Classifies a single ChecklistBank nameusage search response into the
  # status vocabulary FamilyRefresh#classify_family switches on. Split out
  # of CatalogueOfLife itself (mirroring FamilyRefresh::Report) to keep the
  # main class under Metrics/ClassLength; pure data in, pure hash out, no
  # HTTP and no knowledge of the client that fetched the page.
  class SynonymClassifier
    def self.call(name, page)
      new(name, page).call
    end

    def initialize(name, page)
      @name = name
      @page = page
    end

    def call
      hit ? classify(hit) : { status: :not_found }
    end

    private

    attr_reader :name, :page

    # The search endpoint matches q as a prefix/fuzzy query, not an exact
    # name, so the queried name itself may not be the first (or only) result.
    def hit
      (page['result'] || []).find { |r| r.dig('usage', 'name', 'scientificName')&.casecmp?(name) }
    end

    def classify(hit)
      usage = hit['usage'] || {}
      case usage['status']
      when 'synonym' then { status: :synonym, accepted_name: usage.dig('accepted', 'name', 'scientificName') }
      when 'ambiguous synonym' then { status: :ambiguous_synonym }
      when 'accepted' then { status: :accepted }
      else { status: :not_found }
      end
    end
  end
end
