class FieldListComponentPreview < ViewComponent::Preview
  # The ordinary case: short values beside their labels.
  def inline_values
    render FieldListComponent.new(fields: {
      name: "Hamlet",
      author: "William Shakespeare",
      public: true,
      cancelled: false,
      venue: nil
    })
  end

  # A value given as a Hash gets a heading and a block of its own.
  def block_fields
    render FieldListComponent.new(fields: {
      name: "Hamlet",
      blurb: { type: "markdown", markdown: "**To be**, or not to be." },
      notes: { type: "content", header: "Production notes", content: "Performed in the round." }
    })
  end

  # On the admin site an image field also offers the original.
  def with_an_image
    picture = Picture.first
    return render FieldListComponent.new(fields: { name: "No pictures in this database" }) if picture.nil?

    render FieldListComponent.new(
      fields: { poster: { type: "image", image: picture.image, variant: helpers.thumb_variant } },
      admin_site: true
    )
  end
end
