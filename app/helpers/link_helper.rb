module LinkHelper
  def user_link(user, use_public_link_as_fallback)
    return 'User Not Found' if user.nil?

    name = user.name(current_ability)

    if current_ability.can?(:read, user)
      return link_to name, admin_user_path(user)
    elsif use_public_link_as_fallback && current_ability.can?(:view_shows_and_bio, user)
      return link_to name, user_path(user)
    else
      return name
    end
  end

  def link_to_add(form, attribute_name, object_name: nil, html_class: nil)
    html_class ||= 'btn'
    object_name ||= format_class_name(attribute_name.to_s, true)

    return form.link_to_add add_button_text(object_name), attribute_name, class: html_class
  end

  def add_button_text(object_name)
    return "<i class=\"fa fa-plus\" aria-hidden=\"true\"></i> Add #{object_name}".html_safe
  end

  def link_to_remove(form, link_text: nil, html_class: nil)
    html_class ||= 'btn btn-danger'

    return form.link_to_remove remove_button_text(link_text), class: html_class
  end

  def remove_button_text(text = nil)
    text ||= 'Remove'

    return "<i class=\"fa fa-trash\" aria-hidden=\"true\"></i> #{text}".html_safe
  end

  def get_link(object, action, link_text: nil, prefix: nil, append_name: nil, link_target: nil, condition: nil, additional_condition: true, return_link_text_if_no_permission: nil, html_class: nil, wrap_tag: nil, admin: true, confirm: nil, detail: nil, type_confirm: nil, http_method: nil, title: nil, anchor: nil, target: nil, no_wrap: false, query_params: {})
    raise(ArgumentError, 'The object is nil') if object.nil?

    # Make sure the action is a symbol. This works even if the action is already a symbol.
    action = action.to_s.parameterize(separator: '_').to_sym

    additional_message = 'Did you mean "new"? ' if action == :create
    additional_message = 'Did you mean "edit"? ' if action == :update
    additional_message = 'Did you mean "destroy"? ' if action == :delete

    if additional_message.present?
      raise(ArgumentError, "#{additional_message}. \"#{action}\" is not a valid GET action.")
    end

    # TODO: Check if the action is a member and/or collection action instead of having a list like this.
    if %I[index grid new].include?(action) && !object.is_a?(Class)
      # The object has to be a class because those actions are not related to instances.
      # Grid is used as a class thing once and as an instance(or rather, slug thing) the other time.

      raise(TypeError, "#{object} is an instance and not a class so it cannot be #{action}'ed. The allowed actions that are executable on classes are hard-coded, and you can modify them in the link-helper.")
    elsif %i[edit show destroy reject approve answer create update delete].include?(action) && object.is_a?(Class)
      raise(TypeError, "#{object} is a class and not an instance so it cannot be #{action}'ed.") 
    end

    condition = current_ability.can?(action, object) && additional_condition if condition.nil?

    unless condition
      if return_link_text_if_no_permission || (return_link_text_if_no_permission.nil? && action == :show)
        return generate_link_text(link_text, object, action, prefix, append_name)
      else
        return unless condition
      end
    end

    link_text = generate_link_text(link_text, object, action, prefix, append_name)

    # You might notice that the names of the variables given do not match the parameter names defined in the function definition.
    # We switched from data confirmation plugins, and they have a different naming convention.
    # To prevent having to change all existing code that called this function (get_link). I left the names of the parameters of this function intact,
    # and only changed it within the get_confirm_data function.
    confirm_data = get_confirm_data(object, action, confirm, detail, type_confirm)

    namespace = get_namespace_for_link(object, admin)

    link_target = get_default_link_target(object, action, namespace, anchor, query_params) if link_target.nil?
    http_method = get_default_http_method(action) if http_method.nil?
    html_class = get_default_html_class(action) if html_class.nil?

    html_class = "#{html_class} no-wrap" if no_wrap

    # Removes prepending pencil tags and such.
    title ||= strip_tags(link_text).strip

    link = link_to(link_text, link_target, class: html_class, method: http_method, data: confirm_data, title: title, target: target)

    link = wrap_in_tags(link, wrap_tag) if wrap_tag

    return link
  end

  def wrap_in_tags(content, wrap_tag)
    return "<#{wrap_tag}>#{content}</#{wrap_tag}>".html_safe
  end

  def get_namespace_for_link(object, is_admin)
    model_namespace = (object.is_a?(Class) ? object : object.class).name.split('::').first

    namespace = is_admin && model_namespace != 'Admin' ? :admin : nil

    return namespace
  end

  private

  def generate_link_text(link_text, object, action, prefix, append_name)
    return link_text.to_s unless link_text.nil?

    if prefix.nil?
      case action
      when :show
        link_text = get_object_name(object, "Show #{get_formatted_class_name(object)}")
      when :index
        prefix = generate_icon_prefix('th-list', 'Show All')
        append_name = true if append_name.nil?
      when :new
        prefix = generate_icon_prefix('plus', 'New')
        append_name = true if append_name.nil?
      when :edit
        prefix = generate_icon_prefix('pencil-alt', 'Edit')
      when :destroy
        prefix = generate_icon_prefix('trash', 'Destroy')
      else #when :reject, :approve
        prefix = action.to_s.humanize.titleize
      end
    end

    name = get_object_name(object)
    name = name.pluralize if action == :index

    link_text ||= "#{prefix}#{" #{name}" if append_name}".html_safe

    return link_text.to_s
  end

  def generate_icon_prefix(icon_name, prefix)
    return "<span class=\"no-wrap\"><i class=\"fa fa-#{icon_name}\" aria-hidden=”true”></i> #{prefix}</span>".html_safe
  end

  def get_default_html_class(action)
    case action
    when :show
      ''
    when :new
      'btn btn-primary'
    when :destroy, :reject
      'btn btn-danger'
    when :approve
      'btn btn-success'
    else
      'btn'
    end
  end

  def get_default_http_method(action)
    case action
    when :show, :index, :edit, :new
      :get
    when :destroy
      :delete
    when :approve, :reject
      :put
    else
      raise(ArgumentError, "There is no default HTTP method for the specified action #{action}")
    end
  end

  def get_default_link_target(object, action, namespace, anchor, query_params)
    query_params.merge(anchor: anchor) if anchor.present?

    params = [namespace, object]

    # For index, object is a class, so it returns the index. For show, it returns the show page.
    if %i[show index destroy].include?(action)
      return polymorphic_path(params, query_params)
    else
      return polymorphic_path_for_action(action, params, query_params)
    end
  end

  def get_confirm_data(object, action, title, confirm, verify)
    return unless action == :destroy || title.present? || confirm.present? || verify.present?

    confirm_data = {
      title: title,
      confirm: confirm,
      verify: verify
    }

    # Destroy has a default hash, that we don't want to use for other confirm dialogs because that could lead to confusion.
    if action == :destroy
      name = get_object_name(object, include_class_name: true, include_the: true)
      confirm_data[:title] ||= "Deleting #{name}"
      confirm_data[:confirm] ||= "Are you sure you want to delete #{name}?"
    end

    return confirm_data
  end
end
