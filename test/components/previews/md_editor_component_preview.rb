class MdEditorComponentPreview < Admin::ApplicationComponentPreview
  # Default — new record (no id yet), default row count
  def default
    render_with_template(locals: { record: User.new })
  end

  # Tall editor — existing record, more rows
  def tall
    render_with_template(locals: { record: User.first! })
  end

  # Custom label via input_field_args
  def custom_label
    render_with_template(locals: { record: User.new })
  end

  # The public forms' stacked layout, shown beside a plain vertical field so the
  # two can be checked against each other.
  def vertical
    render_with_template(locals: { record: User.new })
  end
end
