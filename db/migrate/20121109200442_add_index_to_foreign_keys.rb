class AddIndexToForeignKeys < ActiveRecord::Migration
  def change
    add_index :admin_proposals_answers, :question_id
    add_index :admin_proposals_answers, :proposal_id
    add_index :admin_proposals_proposals, :call_id
    add_index :admin_staffing_jobs, :staffing_id
    add_index :admin_staffing_jobs, :user_id
    add_index :admin_staffings, :reminder_job_id
    add_index :attachments, :editable_block_id
    add_index :team_members, :user_id
    add_index :team_members, :teamwork_id
    add_index :team_members, :teamwork_type
  end
end
