module Sluggable
  extend ActiveSupport::Concern

  SLUG_FORMAT = /\A[a-z0-9]+([a-z0-9\-]*[a-z0-9]+)?\z/

  included do
    validates :slug, format: {
      with: SLUG_FORMAT,
      message: "may only contain lowercase letters, numbers, and hyphens, and must start and end with a letter or number"
    }
  end
end
