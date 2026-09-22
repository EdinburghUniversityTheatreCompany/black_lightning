module Admin::ProposalsHelper
  def can_act_on_proposals(proposals)
    can?(:approve, Admin::Proposals::Proposal) || proposals.any? { |p| can?(:withdraw, p) }
  end

  def proposal_action_buttons(proposal)
    if can?(:approve, proposal)
      buttons =
        case proposal.status
        when :awaiting_approval
          approve_link = proposal.has_debtors ?
            get_link(proposal, :approve, confirm: "Approving #{proposal.show_title}", detail: "Warning: You are attempting to approve a show with debtors.\n Please type 'Ignoring Debt' to confirm", type_confirm: "Ignoring Debt") :
            get_link(proposal, :approve)

          [ approve_link, get_link(proposal, :reject) ]
        when :approved
          [ get_link(proposal, :mark_successful),
            get_link(proposal, :mark_unsuccessful) ]
        else
          []
        end

      buttons << get_link(proposal, :revert_status, link_text: "Revert", confirm: "Are you sure you want to revert this proposal") unless proposal.awaiting_approval?
    else
      buttons = []
    end

    if can?(:withdraw, proposal)
      if proposal.withdrawn?
        buttons << get_link(proposal, :unwithdraw)
      else
        buttons << get_link(proposal, :withdraw, confirm: "are you sure you want to withdraw this ")
      end
    end

    buttons
  end

  def proposal_labels(proposal, pull_right, show_debtors: true)
      hide_status_label = proposal.withdrawn? && proposal.status == :awaiting_approval

      labels = []
      labels << generate_label(proposal.label_css_class, proposal.formatted_status) unless hide_status_label
      labels << generate_label("bg-info", "Withdrawn") if proposal.withdrawn?
      labels << generate_label("bg-danger", "Late") if proposal.late
      labels << generate_label("bg-danger", "Has Debtors") if show_debtors && proposal.has_debtors

      labels_html = safe_join(labels, "\n")

      return content_tag(:div, labels_html, class: "float-right") if pull_right

      labels_html
  end
end
