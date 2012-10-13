class Show < ActiveRecord::Base
  resourcify
  def to_param
    slug
  end

  attr_accessible :description, :name, :slug, :tagline, :xts_id
end
