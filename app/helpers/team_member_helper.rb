module TeamMemberHelper
    # Generate the labels to be shown in the team member list.
    # Deadline is the proposal deadline, if applicable.
    def team_member_labels_for(team_member, deadline)
        output_labels = []

        output_labels << { label_class: :info, text: 'DM Trained' } if team_member.user.has_role?('DM Trained') 

        output_labels << { label_class: :success, text: 'First Aid Trained' } if team_member.user.has_role?('First Aid Trained')

        # Display the 'Not a Member' label if the show is this academic year, or it has a deadline in the future (and is likely a proposal)
        show_member_status =  (team_member.teamwork_type == 'Event' && team_member.teamwork.this_academic_year?) || (deadline.present? && deadline.future?)
        output_labels << { label_class: :secondary, text: 'Not A Member' } if !team_member.user.has_role?('Member') && show_member_status

        if team_member.user.in_debt
            debt_message = team_member.user.debt_message_suffix.upcase_first

            output_labels << { label_class: :danger, text: link_to(debt_message, admin_debt_path(team_member.user)) }
        end 

        if deadline.present? && team_member.user.in_debt(deadline)
            on_deadline_debt_message = team_member.user.debt_message_suffix(deadline).upcase_first 

            # Only show the deadline message if the debt on the deadline is different. 
            if on_deadline_debt_message != debt_message
                on_deadline_debt_message = "#{on_deadline_debt_message} on the editing deadline"
                output_labels << { label_class: :danger, text: link_to(on_deadline_debt_message, admin_debt_path(team_member.user)) }
            end  
        end

        return output_labels
    end
end
