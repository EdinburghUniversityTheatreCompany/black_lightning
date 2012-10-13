class News < ActiveRecord::Base
  def to_param
    "#{id}-#{slug}"
  end

  attr_accessible :publish_date, :show_public, :slug, :title, :body
end
