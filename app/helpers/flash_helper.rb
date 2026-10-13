module FlashHelper
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

  # The hash the layout's SweetAlert script reads. Discards the flash so a cached or
  # re-rendered page cannot replay it.
  def flash_alerts_for_script
    standardise_flash
    alert_hash = flash_as_alert_hash
    flash.discard
    alert_hash
  end

  # The flash as { type => [messages] }, highest priority first. The messages stay plain text:
  # the browser sets them as text, so a name or title in one cannot inject markup.
  def flash_as_alert_hash
    priority_order = [ :error, :info, :warning, :success ]

    flash.sort_by { |key, _| priority_order.index(key.to_sym) || Float::INFINITY }
         .to_h { |key, messages| [ key.to_sym, messages ] }
  end
end
