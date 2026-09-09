# frozen_string_literal: true

# The safety concept for Food Plants International records (fpi-connector
# decisions 23, 32, 47, 48; schema-delta item 5).
#
# FPI marks 863 of its 34,701 plants with a safety token in the free-text
# `Edible portion` field (`Caution`, `Seeds (POISONOUS)`) and 1,042 as of
# uncertain edibility (`?`, `Unsure`, or the family Amanitaceae). Those
# annotations must survive the import as structured data, never as prose
# that a reader might miss.
#
#   safety_level        'none' | 'caution' | 'poisonous'. 'none' means no
#                       warning recorded -- not an assertion of safety. Every
#                       existing plant gets 'none'. A varchar with a CHECK
#                       rather than a Postgres enum, so a level can be added in
#                       one migration (the publication_state convention).
#   edibility_uncertain Orthogonal to the level: a record can carry both
#                       `Caution` and `?`.
#   safety_warning      Generated and stored by Postgres from the level, so it
#                       cannot drift from it and cannot be written. Backed by
#                       the partial index for the hasSafetyWarning filter,
#                       since 97.8% of rows are 'none'.
#
# The note itself (`Seeds (POISONOUS)`) is a Mobility-translated attribute in
# plants.translations (safety_note) and needs no column.
class AddSafetyConceptToPlants < ActiveRecord::Migration[8.1]
  def change
    add_column :plants, :safety_level, :string, null: false, default: 'none'
    add_column :plants, :edibility_uncertain, :boolean, null: false, default: false
    add_check_constraint :plants, "safety_level IN ('none','caution','poisonous')",
                         name: 'plants_safety_level_check'
    add_column :plants, :safety_warning, :virtual, type: :boolean, as: "safety_level <> 'none'", stored: true
    add_index :plants, :safety_level, where: "safety_level <> 'none'",
                                      name: 'index_plants_on_safety_level_flagged'
  end
end
