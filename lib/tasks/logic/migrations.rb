class Tasks::Logic::Migrations
  def self.fix_editing_deadline
    counter = 0
    Admin::Proposals::Call.all.each do |call|
      next if call.editing_deadline.present?

      call.update_attribute(:editing_deadline, call.submission_deadline)
      counter += 1
    end

    return counter
  end
end