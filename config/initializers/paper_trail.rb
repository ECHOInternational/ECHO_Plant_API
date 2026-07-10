# frozen_string_literal: true

require Rails.root.join('lib', 'paper_trail_yaml_serializer')

# Ruby 3.1 / Psych 4 rung: point PaperTrail at a safe_load-based YAML serializer
# with an explicit permitted_classes allowlist, instead of PaperTrail 12.3's
# default which falls back to YAML.unsafe_load on Psych 4. See
# lib/paper_trail_yaml_serializer.rb for the full rationale (including why
# ActiveRecord's yaml flags cannot govern this code path).
PaperTrail.serializer = PaperTrailYamlSerializer
