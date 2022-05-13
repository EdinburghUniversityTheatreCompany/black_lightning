module NameHelper
  # Returns the name, title, or subject attribute of the object passed, if present.
  # Otherwise, it resorts to the default. If a default is not specfied, it will resort to the class name.
  # The class name will be formatted. Admin::Questionnaires::QuestionnaireExample returns Questionnaire Example.
  # If include class name is set to true, the result is "The Venue Bedlam Theatre" instead of "Bedlam Theatre".
  # There is an additional bool to disable the the. The class name will not be included if it would result in 
  # a double class name, when the object does not have a name of its own, like "The Venue Venue".
  # Returns nil if the object is nil.
  # Returns the formatted class name if the object is a class.
  def get_object_name(object, default = nil, include_class_name: false, include_the: false)
    return 'Nil' if object.nil?

    return get_formatted_class_name(object) if object.is_a?(Class)

    output = object.try(:to_label) || object.try(:name) || object.try(:title) || object.try(:subject) || object.try(:show_title) || default

    if output.present? && include_class_name
      output = "#{get_formatted_class_name object} \"#{output}\""
    end

    output ||= get_formatted_class_name(object)

    output = "the #{output}" if include_the

    return output
  end

  # Returns the formatted class name of the passed class or instance.
  # Admin::Questionnaires::QuestionnaireExample returns Questionnaire Example.
  # Returns nil if the object is nil.
  def get_formatted_class_name(subject_class, singular = true)
    return 'Nil' if subject_class.nil?

    subject_class = subject_class.class unless subject_class.is_a? Class

    return format_class_name(subject_class.name, singular)
  end

  def format_class_name(name, singular = true)
    name = name.to_s.demodulize.underscore.humanize.titleize

    name = name.singularize if singular
    name = name.pluralize unless singular

    return name
  end
end
