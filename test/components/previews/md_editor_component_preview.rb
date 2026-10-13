class MdEditorComponentPreview < Admin::ApplicationComponentPreview
  def default
    render_with_template(locals: { record: User.new })
  end

  def tall
    render_with_template(locals: { record: User.first! })
  end

  def custom_label
    render_with_template(locals: { record: User.new })
  end

  # The public forms' layout, beside a plain vertical field for comparison.
  def vertical
    render_with_template(locals: { record: User.new })
  end
end
