# frozen_string_literal: true

class AddFamilyToPlants < ActiveRecord::Migration[8.1]
  def change
    add_reference :plants, :family, type: :uuid, null: true, foreign_key: true,
                                    index: { name: 'index_plants_on_family_id' }
  end
end
