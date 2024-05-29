class AlterAdminProposalsProposal < ActiveRecord::Migration[7.0]
  def up
    add_column :admin_proposals_proposals, :status, :bigint, null: false

    Admin::Proposals::Proposal.all.each do |proposal|
      proposal.status = case proposal.successful
      when nil
        case proposal.approved
        when nil
          0
        when true
          1
        when false
          2
        end
      when true
        3
      when false
        4
      end

      proposal.save(validate: false)
    end

    remove_column :admin_proposals_proposals, :approved, :boolean
    remove_column :admin_proposals_proposals, :successful, :boolean
  end

  def down
    add_column :admin_proposals_proposals, :approved, :boolean
    add_column :admin_proposals_proposals, :successful, :boolean

    Admin::Proposals::Proposal.all.each do |proposal|
      p "#{proposal.status} -> #{Admin::Proposals::Proposal.statuses[proposal.status]}"
      case Admin::Proposals::Proposal.statuses[proposal.status]
      when 0
        proposal.update(approved: nil, successful: nil)
      when 1
        proposal.update(approved: true, successful: nil)
      when 2
        proposal.update(approved: false, successful: nil)
      when 3
        proposal.update(approved: true, successful: true)
      when 4
        proposal.update(approved: true, successful: false)
      end
    end

    remove_column :admin_proposals_proposals, :status, :bigint, null: false
  end
end
