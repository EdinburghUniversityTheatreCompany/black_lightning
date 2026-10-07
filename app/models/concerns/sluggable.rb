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
    # Generates the slug from +attribute+ until someone sets one by hand.
    def slug_from(attribute)
      before_validation { generate_slug_from(attribute) }
    end
  end

  private

  def generate_slug_from(attribute)
    return unless public_send(attribute).present?
    return if slug.present? && !attribute_changed?(attribute)

    base_slug = public_send(attribute).to_url

    # A renamed record keeps a hand-set slug: only one still matching the old value
    # (or its -N suffix) was generated. A new record's pre-set slug is hand-set.
    if attribute_changed?(attribute) && slug.present?
      old_slug = attribute_was(attribute)&.to_url
      return if old_slug.nil?
      return unless slug == old_slug || slug.start_with?("#{old_slug}-")
    end

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
