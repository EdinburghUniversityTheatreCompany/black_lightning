class ImageComponentPreview < ViewComponent::Preview
  def default
    render ImageComponent.new(image: sample_image, variant: helpers.medium_variant, alt: "A poster")
  end

  # A thumbnail sized by its caller rather than stretched to the column.
  def fixed_width
    render ImageComponent.new(image: sample_image, variant: helpers.square_thumb_variant,
                              full_width: false, alt: "An avatar",
                              image_options: { class: "rounded" })
  end

  # The masthead: the one image on a page that should not wait to load.
  def priority
    render ImageComponent.new(image: sample_image, variant: helpers.slideshow_variant,
                              proxy: true, priority: true, alt: "Tonight's show")
  end

  # Offers the smaller variants so a phone does not fetch a 960px card.
  def responsive
    render ImageComponent.new(image: sample_image, variant: helpers.medium_variant, proxy: true,
                              srcset_variants: [ helpers.thumb_variant_public, helpers.medium_variant, helpers.slideshow_variant ],
                              alt: "A poster")
  end

  private

  def sample_image
    Picture.first&.fetch_image
  end
end
