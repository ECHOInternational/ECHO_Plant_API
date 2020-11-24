class AddEvaluatedAtToSpecimens < ActiveRecord::Migration[6.0]
  def change
    add_column :specimens, :evaluated_at, :datetime
  end
end
