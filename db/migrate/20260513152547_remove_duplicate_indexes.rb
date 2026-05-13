class RemoveDuplicateIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :admin_answers, name: "index_admin_answers_on_answerable_id"
    remove_index :admin_answers, name: "index_admin_proposals_answers_on_proposal_id"

    remove_index :admin_staffing_jobs, name: "index_admin_staffing_jobs_on_staffable_id"
    remove_index :admin_staffing_jobs, name: "index_admin_staffing_jobs_on_staffing_id"
  end
end
