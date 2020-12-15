class AddDeletedToLifeCycleEvents < ActiveRecord::Migration[6.0]
  def change
    add_column :life_cycle_events, :deleted, :boolean, default: false
  end
end
