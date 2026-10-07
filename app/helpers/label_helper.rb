module LabelHelper
    # Labels for the team member list and the user profile. `deadline` is the proposal deadline,
    # if any; `show_member_status_when` is :positive, :negative, :always or :never; `exhaustive`
    # adds role labels such as Admin.
    def user_labels_for(user, deadline, show_member_status_when = :never, exhaustive = false)
        output_labels = []

        if show_member_status_when != :never
            is_life_member = user.has_role?("life member")
            is_eutc_member = user.member?

            show_member_status = case show_member_status_when
            when :positive; is_eutc_member
            when :negative; !is_eutc_member
            when :always; true
            end

            if show_member_status
                if is_life_member
                    if show_member_status_when != :negative
                        output_labels << { label_class: "bg-rainbow-rotate", text: "Life Member" }
                    end

                    if is_eutc_member
                        output_labels << { label_class: "bg-info", text: "EUTC Member" }
                    else
                        output_labels << { label_class: "bg-secondary", text: "Non-EUTC Member" }
                    end
                elsif is_eutc_member
                    output_labels << { label_class: "bg-info", text: "Member" }
                else
                    output_labels << { label_class: "bg-secondary", text: "Non-Member" }
                end
            end
        end

        if exhaustive && user.admin?
            output_labels << { label_class: "bg-admin-rotate", text: "Admin" }
        end

        user.roles.trained.each do |role|
            label_class = role.name == "First Aid Trained" ? "bg-success" : "bg-info"
            output_labels << { label_class: label_class, text: role.name }
        end

        now = debt_kinds(user, Date.current)
        output_labels << debt_label(user, now, (" now" if deadline.present?)) if now.any?

        if deadline.present?
            later = debt_kinds(user, deadline) - now
            output_labels << debt_label(user, later, " on the editing deadline") if later.any?
        end

        output_labels
    end

    def team_member_labels_for(team_member, deadline)
        # Non-members are flagged on this year's shows and on proposals still open.
        show_member_status = (team_member.teamwork_type == "Event" && team_member.teamwork.this_academic_year?) || (deadline.present? && deadline.future?)

        show_member_status_when = show_member_status ? :negative : :never
        user_labels_for(team_member.user, deadline, show_member_status_when)
    end

    def user_profile_labels_for(user)
        user_labels_for(user, nil, :always, true)
    end

    BADGE_CLASS_MAP = BadgeComponent::STYLES.transform_keys { |type| "bg-#{type}" }.freeze

    def generate_label(label_class, message, pull_right = false, rounded = false)
        label_class = label_class&.to_s
        mapped = BADGE_CLASS_MAP[label_class] || label_class
        mapped += " rounded-full" if rounded
        mapped += " float-right" if pull_right

        message = ActionController::Base.helpers.sanitize message

        "<span class=\"inline-flex items-center rounded px-2 py-0.5 text-xs font-medium #{mapped}\">#{message}</span>".html_safe
    end

    private

    def debt_kinds(user, on_date)
        kinds = []
        kinds << "staffing" if user.debt_causing_staffing_debts(on_date).any?
        kinds << "maintenance" if user.debt_causing_maintenance_debts(on_date).any?
        kinds
    end

    def debt_label(user, kinds, suffix)
        { label_class: "bg-danger", text: link_to("In #{kinds.join(' and ')} debt#{suffix}", admin_debt_path(user)) }
    end
end
