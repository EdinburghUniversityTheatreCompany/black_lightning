module LabelHelper
  def generate_label(label_class, message, pull_right = false, rounded = false)
    label_class = label_class&.to_s

    valid_classes = %w[primary secondary danger success info warning light dark].freeze
    raise(ArgumentError, "#{label_class} is not a valid label class. Use one of #{valid_classes.to_sentence}.") if valid_classes.exclude?(label_class)

    label_class = "#{label_class} text-dark" if %w[warning info light].include?(label_class)
    # TODO: Test the proper generated classes and stuff

    label_class = "#{label_class} rounded-pill" if rounded

    message = ActionController::Base.helpers.sanitize message

    # BOOTSTRAP CHECK: Do we need the margin?
    return "<span style=\"margin-right: 5px;\" class=\"badge bg-#{label_class}#{' float-right' if pull_right}\">#{message}</span>".html_safe
  end
end
