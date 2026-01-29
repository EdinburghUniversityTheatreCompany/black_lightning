class AddStudentIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :student_id, :string
    add_index :users, :student_id

    reversible do |dir|
      dir.up do
        # Extract student IDs from existing users' emails
        User.reset_column_information
        User.find_each do |user|
          if user.email.present? && user.email.match?(/\A(s\d{7})@ed\.ac\.uk\z/i)
            student_id = user.email.match(/\A(s\d{7})@ed\.ac\.uk\z/i)[1].downcase
            user.update_column(:student_id, student_id)
          end
        rescue => e
          # Skip on error as requested
          Rails.logger.warn "Failed to extract student_id for user #{user.id}: #{e.message}"
        end
      end
    end
  end
end
