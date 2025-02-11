class CreateDevices < ActiveRecord::Migration[8.0]
  def change
    # temporary disable as the table is already in production
    # create_table :devices do |t|
    #   t.string :mode, null: false, default: 'tempo'
    #   t.timestamps
    # end
  end
end
