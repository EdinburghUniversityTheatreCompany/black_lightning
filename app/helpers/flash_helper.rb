module FlashHelper
  include FormattingHelper

  def swal_alert_info(key)
    case key.to_sym
    when :error, :alert
      "error"
    # Notice is only really used by devise, and only for success messages.
    when :success, :notice
      "success"
    when :warning
      "warning"
    else
      "info"
    end
  end

  # Adds a message to the flash hash, ensuring that it is an array, and that every message occurs only once.
  def append_to_flash(key, message)
    if flash[key].blank?
      flash[key] = [ message ]
    elsif flash[key].is_a? Enumerable
      flash[key] << message
    else
      flash[key] = [ flash[key], message ]
    end

    flash[key] = flash[key].uniq
  end

  # Turns all flash messages into arrays, merges 'alerts' into 'errors', and merges 'notices' in to 'successes'.
  def standardise_flash
    # Convert each flash type into an array if it is not already.
    # The to_h is to make a local copy so we can assign to the real flash.
    # If you do not do this, it would say you cannot assign during iteration
    # and because flash is not a real hash, it does not have all methods and you
    # cannot perform in-place operations.
    flash.to_h.each { |key, value| flash[key] = Array(value) }

    # Alert is just an alias for error, so merge them here.
    if flash[:alert].present?
      flash[:error] = [] unless flash[:error].present?

      flash[:error] += flash[:alert]

      flash.delete(:alert)
    end

    # Similarly for success
    if flash[:notice].present?
      flash[:success] = [] unless flash[:success].present?

      flash[:success] += flash[:notice]
      flash.delete(:notice)
    end
  end

  # This method is used to convert the flash into a hash that has all keys in the correct order and every message html formatted.
  def flash_as_alert_hash
    alert_hash = {}

    # Order to display flash messages in, from highest to lowest priority.
    priority_order = [ :error, :info, :warning, :success ]

    # Sort the flash keys by the priority order and iterate over them
    flash.sort_by { |key, _| priority_order.index(key.to_sym) || Float::INFINITY }.each do |key, messages|
      # If there is a single message, use that. If there are multiple, render them as an HTML list.
      alert_hash[key.to_sym] = messages.count <= 1 ? messages.first : render_as_list(messages, "ul")
    end

    alert_hash
  end
end
