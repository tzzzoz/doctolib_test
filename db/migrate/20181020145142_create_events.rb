class CreateEvents < ActiveRecord::Migration[5.1]
  def change
    create_table :events do |t|
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :kind
      t.boolean :weekly_recurring
      t.integer :days_to_week

      t.timestamps
    end
  end
end
