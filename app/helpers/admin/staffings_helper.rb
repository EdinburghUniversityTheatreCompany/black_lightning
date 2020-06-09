module Admin::StaffingsHelper
  include ApplicationHelper
  
  def check_if_current_user_can_sign_up(user, job = nil)
    case job&.downcase
    when 'committee rep'
      unless user.has_role?('Committee')
        append_to_flash(:error, 'You are not on committee. If you think this is a mistake, please contact the Secretary.')
        return false
      end
    when 'duty manager', 'dungeon master'
      unless user.has_role?('DM Trained') || user.has_role?('Committee')
        append_to_flash(:error, 'You are not DM Trained. If you think this is a mistake, please contact the Theatre Manager.')
        return false
      end
    end

    return user.phone_number.present? && user.can?(:sign_up_for, Admin::StaffingJob)
  end
end
