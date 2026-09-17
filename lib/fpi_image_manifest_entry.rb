# frozen_string_literal: true

# What FpiImageImporter did with each manifest row, plus the FPI images the
# manifest no longer names (counted, never deleted).
FpiImageImportTotals = Struct.new(:created, :unchanged, :replaced, :reparented, :retagged, :missing_plant, :not_uploaded, :invalid,
                                  :absent_from_manifest, :details, keyword_init: true) do
  def self.empty
    new(**(members - [:details]).index_with(0), details: [])
  end

  def to_h
    super.except(:details)
  end
end

# One row of an FPI image manifest (see FpiImageImporter), validated against
# the key createSourceUpload issues in this environment.
FpiImageManifestEntry = Struct.new(:kind, :rowid, :plant_id, :key, :sha256, :bytes, :name, keyword_init: true) do
  # uuid5 namespace for FPI image ids, itself uuid5(NAMESPACE_URL,
  # "https://plant-api.echocommunity.org/fpi/images"). Never change it: every
  # image id is uuid5(NAMESPACE, "photos:<ROWID>" | "drawings:<ROWID>").
  const_set(:NAMESPACE, '16a87c19-75a8-5fe7-9c8f-d3022d36adfe')
  const_set(:KINDS, %w[photo drawing].freeze)

  def self.from(hash)
    new(**hash.slice(*members.map(&:to_s)).transform_keys(&:to_sym))
  end

  def source_record_id
    "#{kind}s:#{rowid}"
  end

  def image_id
    Digest::UUID.uuid_v5(self.class::NAMESPACE, source_record_id)
  end

  def drawing?
    kind == 'drawing'
  end

  def problem(source_system_key)
    shape_problem || key_problem(source_system_key)
  end

  private

  def shape_problem
    return 'kind must be photo or drawing' unless self.class::KINDS.include?(kind)
    return 'rowid must be a positive integer' unless rowid.is_a?(Integer) && rowid.positive?
    return 'sha256 must be 64 hex' unless sha256.to_s.match?(/\A[0-9a-f]{64}\z/)

    'name is blank' if name.to_s.strip.empty?
  end

  def key_problem(source_system_key)
    expected = Mutations::CreateSourceUpload.image_key(source_system_key, kind, File.basename(key.to_s))
    "key #{key.inspect} is not the key createSourceUpload issues here (#{expected})" unless key == expected
  end
end
