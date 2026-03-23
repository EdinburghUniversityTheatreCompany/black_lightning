module LabelHelper
  def generate_label(label_class, message, pull_right = false, rounded = false)
    label_class = label_class&.to_s

    label_class = "#{label_class} text-dark" if %w[bg-warning bg-info bg-light].include?(label_class)
    # TODO: Test the proper generated classes and stuff

    label_class = "#{label_class} rounded-pill" if rounded

    message = ActionController::Base.helpers.sanitize message

    "<span class=\"badge #{label_class}#{' float-right' if pull_right}\">#{message}</span>".html_safe
  end
end
