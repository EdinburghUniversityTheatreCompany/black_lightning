class UpdateProposalCallWithNewConstitution < ActiveRecord::Migration[5.0]
  def up
    change_table :admin_proposals_calls do |t|
      t.remove :open
      t.rename :deadline, :submission_deadline
      t.datetime :editing_deadline
    end

    Admin::Proposals::Call.all.each do |call|
      call.update_attribute(:editing_deadline, call.submission_deadline)
    end
  end

  def down
    change_table :admin_proposals_calls do |t|
      t.remove :editing_deadline
      t.rename :submission_deadline, :deadline
      t.boolean :open
    end
  end
end
