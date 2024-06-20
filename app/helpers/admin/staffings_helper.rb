module Admin::StaffingsHelper
  include FlashHelper
  
  def check_if_current_user_can_sign_up(user, job = nil)
    can_sign_up = user.can?(:sign_up_for, Admin::StaffingJob)
    
    unless can_sign_up
      append_to_flash(:error, 'You do not have the appropriate permission to sign up for staffing slots.')
    end

    case job&.downcase
    when 'committee rep', 'committee', 'committee representative', 'cr'
      unless user.has_role?('Committee')
        append_to_flash(:error, 'You are not on committee. If you think this is a mistake, please contact the Secretary.')
        can_sign_up = false
      end
    when 'duty manager', 'dm', 'dungeon master'
      unless user.has_role?('DM Trained') || user.has_role?('Committee')
        append_to_flash(:error, 'You are not DM Trained. If you think this is a mistake, please contact the Theatre Manager.')
        can_sign_up = false
      end
    end

    unless user.phone_number.present?
      append_to_flash(:error, 'You need to provide your phone number before you can sign up to staff.')
      can_sign_up = false
    end

    return can_sign_up
  end
end
