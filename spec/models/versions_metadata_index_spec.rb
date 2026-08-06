# frozen_string_literal: true

require 'rails_helper'

# The aggregated record history finds child versions with
# `versions.metadata @> '{"root_type":...,"root_id":...}'`. That containment
# operator is only indexable by a GIN index; jsonb_path_ops supports exactly
# the @> operator and is about half the size of the default jsonb_ops.
RSpec.describe 'versions.metadata GIN index', type: :model do
  it 'indexes versions.metadata with a GIN index for containment lookups' do
    index = ActiveRecord::Base.connection.indexes('versions').find do |i|
      i.name == 'index_versions_on_metadata_jsonb_path_ops'
    end

    expect(index).not_to be_nil
    expect(index.using).to eq(:gin)
    expect(index.columns).to eq(['metadata'])
  end
end
