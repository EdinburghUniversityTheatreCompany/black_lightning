class Tasks::Logic::Users
  def self.clean_up_personal_info
    consented_date_range = Date.today.advance(years: -100)..Date.today.advance(years: -1)
    
    users = User.where(consented: consented_date_range)
                .where.not(phone_number: nil)

    users.each do |user|
      user.phone_number = nil
      p "#{user.name_or_email}: Cleared phone number"

      unless user.save
        # :nocov:
        p "WARNING: Could not save #{user.name_or_email}"
        # :nocov:
      end
    end

    return users.size
  end
end
