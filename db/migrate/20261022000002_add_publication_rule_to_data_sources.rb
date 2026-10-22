# frozen_string_literal: true

# The single quality setting of the FPI plan (decision Q2, task API-10,
# section 3.2): data_sources.publication_rule, read by PublicationRule.
# NULL means "no quality bar" (every plant of the source meets it), which is
# what ECHO's own records get. FPI is seeded with the wave-1 rule: at least
# one image, or at least 500 characters of English description + uses +
# cultivation (8,172 plants on the 2026-10-22 production copy).
#
# Adding a nullable jsonb column without a default is catalog-only; the seed
# touches one row. The FPI row exists only where FPI was bootstrapped
# (production, staging, rehearsals), so the seed is a no-op elsewhere.
# updated_at is bumped with the seed so plants(updatedSince:) reports the FPI
# plants as changed (their meetsQualityBar value is new).
class AddPublicationRuleToDataSources < ActiveRecord::Migration[8.1]
  FPI_RULE = {
    version: 1, locale: 'en', text_fields: %w[description uses cultivation],
    min_text_chars: 500, image_suffices: true
  }.freeze

  def up
    add_column :data_sources, :publication_rule, :jsonb
    execute <<~SQL.squish
      UPDATE data_sources
      SET publication_rule = #{connection.quote(FPI_RULE.to_json)}::jsonb, updated_at = now()
      WHERE source_system_key = 'fpi'
    SQL
  end

  def down
    remove_column :data_sources, :publication_rule
  end
end
