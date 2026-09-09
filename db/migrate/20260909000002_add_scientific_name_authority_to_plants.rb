# frozen_string_literal: true

# The taxonomic authority of a plant's scientific name (`L.`, `(L.) Merr.`),
# which Food Plants International carries on 34,106 records and which has had
# no home in the API (fpi-connector schema-delta item 6, backlog A13).
#
# Nullable, no default, no length cap (the source maximum is 177 characters),
# not translated: author citations are language-neutral. Never folded into
# scientific_name, which would break cross-source name matching. ECHO's own
# plants stay NULL until a curator supplies a value.
class AddScientificNameAuthorityToPlants < ActiveRecord::Migration[8.1]
  def change
    add_column :plants, :scientific_name_authority, :string
  end
end
