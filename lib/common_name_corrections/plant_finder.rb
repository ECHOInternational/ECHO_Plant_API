# frozen_string_literal: true

require Rails.root.join('lib/catalogue_of_life')

class CommonNameCorrections
  # Finds the plant a correction names.
  #
  # Not string equality: a name in a correction may be one Catalogue of Life
  # now treats as a synonym while the plant is filed under the accepted name.
  # A bare "not found" would report a fix as impossible while the plant sits
  # there under another name.
  #
  # It never guesses. An ambiguous synonym -- COL's own status for a name with
  # no single successor -- is reported rather than resolved, because choosing a
  # successor would be a guess about which taxon the page means.
  class PlantFinder
    Found = Struct.new(:plant, :line, :via_synonym, keyword_init: true)

    ACCEPTED_BUT_ABSENT = 'Catalogue of Life accepts this name, so the plant is either absent ' \
                          'or filed under a synonym of it'
    AMBIGUOUS = 'Catalogue of Life calls it an ambiguous synonym, with no single accepted ' \
                'successor, so no plant was chosen'
    UNKNOWN = 'not found here, and unknown to Catalogue of Life'
    LOOKUP_FAILED = 'Catalogue of Life lookup failed'

    # The Catalogue of Life client is injectable so a spec can exercise every
    # branch of the cascade without reaching the network.
    def initialize(catalogue_of_life: nil)
      @catalogue_of_life = catalogue_of_life
    end

    def call(name)
      plant = exact(name) || insensitive(name)
      return Found.new(plant: plant) if plant

      through_catalogue_of_life(name)
    end

    private

    def exact(name)
      Plant.unscoped.find_by(scientific_name: name)
    end

    def insensitive(name)
      Plant.unscoped.where('lower(scientific_name) = ?', name.downcase).first
    end

    def through_catalogue_of_life(name)
      case (lookup = catalogue_of_life.synonym_lookup(name))[:status]
      when :synonym then under_accepted_name(name, lookup[:accepted_name])
      when :accepted then missing(name, ACCEPTED_BUT_ABSENT)
      when :ambiguous_synonym then missing(name, AMBIGUOUS)
      when :error then missing(name, LOOKUP_FAILED)
      else missing(name, UNKNOWN)
      end
    end

    def under_accepted_name(name, accepted)
      plant = accepted && (exact(accepted) || insensitive(accepted))
      return no_plant_either_way(name, accepted) if plant.nil?

      Found.new(plant: plant, via_synonym: true,
                line: "resolved       #{name} is a synonym; matched the plant filed as #{accepted}")
    end

    def no_plant_either_way(name, accepted)
      missing(name, "Catalogue of Life gives the accepted name as #{accepted || 'unknown'}, " \
                    'and no plant is filed under either')
    end

    def missing(name, reason)
      Found.new(plant: nil, line: "MISSING PLANT  #{name} -- #{reason}")
    end

    def catalogue_of_life
      @catalogue_of_life ||= CatalogueOfLife.new
    end
  end
end
