# frozen_string_literal: true

module RelationSets
  # The `category_set` relation set (schema-delta item 9): the plant's
  # categories as a sorted JSON array of lower-case category UUIDs.
  #
  # Replace-set semantics, the same as updatePlantCategories and unlike the
  # additive EcCategoryImporter rule. An unknown id is a validation error on
  # the plant, so nothing is written for that row and the engine counts it
  # `invalid`. Category rows are not created here: a category is a shared
  # taxonomy the super-admin owns (fpi-connector decision 35).
  module Categories
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    EMPTY = '[]'

    module_function

    def empty
      EMPTY
    end

    def read(plant)
      return EMPTY if plant.new_record?

      dump(CategoriesPlant.where(plant_id: plant.id).pluck(:category_id).map(&:to_s).uniq.sort)
    end

    def parse(value)
      ids = value.is_a?(String) ? JSON.parse(value) : value
      raise ArgumentError, 'category_set must be an array' unless ids.is_a?(Array)

      ids.map { |id| parse_id(id) }.uniq.sort
    end

    def dump(ids)
      JSON.generate(ids)
    end

    def validate(_plant, ids)
      return [] if ids.empty?

      known = Category.unscoped.where(id: ids).pluck(:id).map(&:to_s)
      (ids - known).map { |id| "refers to an unknown category #{id}" }
    end

    def apply(plant, ids)
      current = CategoriesPlant.where(plant_id: plant.id).index_by { |row| row.category_id.to_s }
      (current.keys - ids).each { |id| current[id].destroy! }
      (ids - current.keys).each { |id| CategoriesPlant.create!(plant_id: plant.id, category_id: id) }
    end

    def parse_id(id)
      raise ArgumentError, "category_set entry must be a UUID string, got #{id.inspect}" unless id.is_a?(String)

      normalized = id.strip.downcase
      raise ArgumentError, "category_set entry is not a UUID: #{id.inspect}" unless UUID.match?(normalized)

      normalized
    end
  end
end
