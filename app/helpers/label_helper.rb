module LabelHelper
  def generate_label(label_class, message, pull_right = false)
    label_class = label_class&.to_s

    valid_classes = %w[default primary success info warning danger].freeze
    raise(ArgumentError, "#{label_class} is not a valid label class. Use one of #{valid_classes.to_sentence}.") if valid_classes.exclude?(label_class)

    message = ActionController::Base.helpers.sanitize message

    return "<span style=\"margin-right: 5px;\" class=\"label label-#{label_class}#{' pull-right' if pull_right}\">#{message}</span>".html_safe
  end
end
