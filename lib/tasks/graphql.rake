# frozen_string_literal: true

namespace :graphql do
  namespace :schema do
    desc 'Dump the GraphQL SDL to schema.graphql'
    task dump: :environment do
      File.write(Rails.root.join('schema.graphql'), PlantApiSchema.to_definition)
    end
  end
end
