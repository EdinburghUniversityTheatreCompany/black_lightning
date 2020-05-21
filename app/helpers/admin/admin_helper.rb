module Admin::AdminHelper
  
  # Destroys the passed object and adds a success or error message to the flash.
  # Checks if the current_ability can destroy the object. Also tests with an and for the additional condition.
  # When condition is specified, it does not check for destroy permission and the additional permission.
  # Raises an ArgumentError if the object passed is nil.
  # Raises a TypeError if the object passed is a class, and not an instance.
  def destroy_with_flash_message(object, condition: nil, additional_condition: true, name: nil, success_message: nil, error_message: nil, append_errors_to_error_message: true)
    raise(ArgumentError, 'The object is nil') if object.nil?
    raise(TypeError, "#{object} is a class and not an instance so it cannot be destroyed.") if object.is_a?(Class)

    condition = can?(:destroy, object) && additional_condition if condition.nil?

    return unless condition

    # This code gets the name if there is no name specified.
    # Examples: The Maintenance Debt, The Venue Bedlam Theatre
    object_name = get_object_name(object, '')
    name ||= "The #{get_formatted_class_name(object)}#{" \"#{object_name}\"" if object_name.present?}"

    if object.destroy
      success_message ||= "#{name} has been successfully destroyed."
      flash[:success] = success_message
      return true
    else
      error_message ||= "#{name} could not be destroyed."
      error_message +=  " #{object.errors.messages[:destroy].join('. ')}" if append_errors_to_error_message

      flash[:error] = error_message
      return false
    end
  end

  def destroy_with_flash_message!(object, condition: nil, additional_condition: true, name: nil, success_message: nil, error_message: nil, append_errors_to_error_message: true)
    raise(ActiveRecord::RecordNotDestroyed, flash[:error]) unless destroy_with_flash_message(object, condition: condition, additional_condition: additional_condition, name: name, success_message: success_message, error_message: error_message, append_errors_to_error_message: append_errors_to_error_message)
  end
end