module Sluggable
  extend ActiveSupport::Concern

  SLUG_FORMAT = /\A[a-z0-9]+([a-z0-9\-]*[a-z0-9]+)?\z/

  included do
    validates :slug, format: {
      with: SLUG_FORMAT,
      message: "may only contain lowercase letters, numbers, and hyphens, and must start and end with a letter or number"
    }
  end

  class_methods do
    # Fills a blank slug from +attribute+. A rename leaves the slug alone: it is the
    # record's URL, and links to the old one would 404.
    def slug_from(attribute)
      before_validation { generate_slug_from(attribute) }
    end
  end

  private

  def generate_slug_from(attribute)
    return if slug.present? || public_send(attribute).blank?

    base_slug = public_send(attribute).to_url
    candidate_slug = base_slug
    counter = 1

    # base_class so an Event's slug is unique across Show, Workshop and Season.
    while self.class.base_class.where.not(id: id).where("LOWER(slug) = ?", candidate_slug.downcase).exists?
      candidate_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = candidate_slug
  end
end
