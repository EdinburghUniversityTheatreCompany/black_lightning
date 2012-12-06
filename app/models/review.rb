class Review < ActiveRecord::Base
  belongs_to :show

  attr_accessible :body, :rating, :review_date, :reviewer, :show_id
end
