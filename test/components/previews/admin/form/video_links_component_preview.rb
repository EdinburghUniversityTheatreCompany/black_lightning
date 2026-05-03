class Admin::Form::VideoLinksComponentPreview < Admin::ApplicationComponentPreview
  # Video links section on a Show form
  def default
    render_with_template(locals: { record: Show.first! })
  end
end
