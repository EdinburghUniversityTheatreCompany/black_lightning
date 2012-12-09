class Admin::Feedback < ActiveRecord::Base
  belongs_to :show, :class_name => "Show"

  attr_accessible :body, :show, :show_id
end
