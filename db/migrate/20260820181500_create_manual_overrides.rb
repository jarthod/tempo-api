class CreateManualOverrides < ActiveRecord::Migration[8.0]
  def change
    create_table :manual_overrides do |t|
      t.string :contract, null: false
      t.date :date, null: false
      t.integer :color, null: false
      t.timestamps
    end
    add_index :manual_overrides, [:contract, :date], unique: true
  end
end
