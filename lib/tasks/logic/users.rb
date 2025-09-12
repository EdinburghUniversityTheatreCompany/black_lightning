class Tasks::Logic::Users
  def self.clean_up_personal_info
    users = User.not_consented.where.not(phone_number: nil)

    users.each do |user|
      user.phone_number = nil
      p "#{user.name_or_email}: Cleared phone number"

      unless user.save
        # :nocov:
        p "WARNING: Could not save #{user.name_or_email}"
        # :nocov:
      end
    end

    users.size
  end
end
