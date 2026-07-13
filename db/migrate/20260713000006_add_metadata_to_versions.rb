# frozen_string_literal: true

class AddMetadataToVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :versions, :metadata, :jsonb
  end
end
