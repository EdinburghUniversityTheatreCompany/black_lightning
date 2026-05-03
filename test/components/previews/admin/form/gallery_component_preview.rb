class Admin::Form::GalleryComponentPreview < Admin::ApplicationComponentPreview
  # Gallery section on a Venue form (empty, start open)
  def default
    render_with_template(locals: { record: Venue.first! })
  end
end
