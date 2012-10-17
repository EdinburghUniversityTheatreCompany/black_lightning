class ChangeNewsPublishDateToDatetime < ActiveRecord::Migration
  def self.up
    change_column :news, :publish_date, :datetime

  end

  def self.down
    change_column :news, :publish_date, :datetime
  end
end
