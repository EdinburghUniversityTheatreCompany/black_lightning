module LabelHelper
    # Generate the labels to be shown in the team member list & user profile.
    # `deadline` is the proposal deadline, if applicable.
    # `show_member_status_when` is one of :positive, :negative, :always, :never
    # `exhaustive` is whether to display extra role labels (like admin).
    def user_labels_for(user, deadline, show_member_status_when = :never, exhaustive = false)
        output_labels = []

        if show_member_status_when != :never
            is_life_member = user.has_role?("life member")
            is_member = is_life_member || user.has_role?("member")

            show_member_status = case show_member_status_when
            when :positive; is_member
            when :negative; !is_member
            when :always; true
            end

            if show_member_status
                if is_life_member
                    output_labels << { label_class: "bg-rainbow-rotate", text: "Life Member" }
                elsif is_member
                    output_labels << { label_class: "bg-success", text: "Member" }
                else
                    output_labels << { label_class: "bg-secondary", text: "Not A Member" }
                end
            end
        end

        if exhaustive && user.has_role?("admin")
            output_labels << { label_class: "bg-admin-rotate", text: "Admin" }
        end

        user.roles.trained.each do |role|
            label_class = role.name == "First Aid Trained" ? "bg-success" : "bg-info"
            output_labels << { label_class: label_class, text: role.name }
        end

        if !deadline.present?
            if user.in_debt
                debt_message = user.debt_message_suffix.upcase_first
                output_labels << { label_class: "bg-danger", text: link_to(debt_message, admin_debt_path(user)) }
            end
        else
            in_maintenance_debt_now = user.debt_causing_maintenance_debts.any?
            in_staffing_debt_now = user.debt_causing_staffing_debts.any?

            if deadline.present?
                in_maintenance_debt_then = user.debt_causing_maintenance_debts(deadline).any?
                in_staffing_debt_then = user.debt_causing_staffing_debts(deadline).any?
            else
                in_maintenance_debt_then = in_staffing_debt_then = false
            end

            debt_message_now = if in_maintenance_debt_now && in_staffing_debt_now
                in_maintenance_debt_then = false
                in_staffing_debt_then = false
                "In staffing and maintenance debt"
            elsif in_maintenance_debt_now
                in_maintenance_debt_then = false
                "In maintenance debt"
            elsif in_staffing_debt_now
                in_staffing_debt_then = false
                "In staffing debt"
            end

            debt_message_then = if in_maintenance_debt_then && in_staffing_debt_then
                "In staffing and maintenance debt"
            elsif in_maintenance_debt_then
                "In maintenance debt"
            elsif in_staffing_debt_then
                "In staffing debt"
            end

            if debt_message_now.present?
                debt_message_now = "#{debt_message_now} now" if deadline.present?
                output_labels << { label_class: "bg-danger", text: link_to(debt_message_now, admin_debt_path(user)) }
            end

            if debt_message_then.present?
                debt_message_then = "#{debt_message_then} on the editing deadline"
                output_labels << { label_class: "bg-danger", text: link_to(debt_message_then, admin_debt_path(user)) }
            end
        end

        output_labels
    end

    # Generate the labels to be shown in the team member list.
    # `deadline` is the proposal deadline, if applicable.
    def team_member_labels_for(team_member, deadline)
        # Display the 'Not a Member' label if the show is this academic year, or it has a deadline in the future (and is likely a proposal)
        show_member_status = (team_member.teamwork_type == "Event" && team_member.teamwork.this_academic_year?) || (deadline.present? && deadline.future?)

        show_member_status_when = show_member_status ? :positive : :never
        user_labels_for(team_member.user, deadline, show_member_status_when)
    end

    def generate_label(label_class, message, pull_right = false, rounded = false)
        label_class = label_class&.to_s

        label_class = "#{label_class} text-dark" if %w[bg-warning bg-info bg-light].include?(label_class)
        # TODO: Test the proper generated classes and stuff

        label_class = "#{label_class} rounded-pill" if rounded

        message = ActionController::Base.helpers.sanitize message

        "<span class=\"badge #{label_class}#{' float-right' if pull_right}\">#{message}</span>".html_safe
    end
end
