module Admin::AdminHelper
  include NameHelper

  # Destroys the passed object and adds a success or error message to the flash.
  # Checks if the ability can destroy the object. Also tests with an and for the additional condition.
  # When condition is specified, it does not check for destroy permission and the additional permission.
  # Raises an ArgumentError if the object passed is nil.
  # Raises a TypeError if the object passed is a class, and not an instance.
  def destroy_with_flash_message(object, condition: nil, additional_condition: true, name: nil, success_message: nil, error_message: nil, append_errors_to_error_flash: true, ability: current_ability)
    raise(ArgumentError, 'The object is nil') if object.nil?
    raise(TypeError, "#{object} is a class and not an instance so it cannot be destroyed.") if object.is_a?(Class)

    # This code gets the name if there is no name specified.
    # Examples: The Maintenance Debt, The Venue Bedlam Theatre
    object_name = get_object_name(object, '')
    name ||= "the #{get_formatted_class_name(object)}#{" \"#{object_name}\"" if object_name.present?}"

    condition = ability.can?(:destroy, object) && additional_condition if condition.nil?


    unless condition
      append_to_flash(:error, error_message || "#{name.upcase_first} could not be destroyed.")
      append_to_flash(:error, "You do not have permission to destroy #{name}.") if ability.cannot?(:destroy, object)
      append_to_flash(:error, "The additional condition to destroy #{name} was not fulfilled.") unless additional_condition || additional_condition.nil?
      
      return false
    end

    if object.destroy
      append_to_flash(:success, success_message || "#{name.upcase_first} has been successfully destroyed.")

      return true
    else
      append_to_flash(:error, error_message || "#{name.upcase_first} could not be destroyed.")
      if append_errors_to_error_flash
        (object.errors.messages[:destroy] + object.errors.messages[:base]).each do |message|
          append_to_flash(:error, message)
        end
      end

      return false
    end
  end

  def destroy_with_flash_message!(object, condition: nil, additional_condition: true, name: nil, success_message: nil, error_message: nil, append_errors_to_error_flash: true)
    raise(ActiveRecord::RecordNotDestroyed, flash[:error]) unless destroy_with_flash_message(object, condition: condition, additional_condition: additional_condition, name: name, success_message: success_message, error_message: error_message, append_errors_to_error_flash: append_errors_to_error_flash)
  end

  # def is_active(action)       
  #   params[:action] == action ? "active" : nil        
  # end
end