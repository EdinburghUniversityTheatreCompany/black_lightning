class Review < ActiveRecord::Base
  belongs_to :show

  attr_accessible :body, :rating, :review_date, :organisation, :reviewer, :show_id
end
