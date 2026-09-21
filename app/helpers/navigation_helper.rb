module NavigationHelper
  def public_navbar_items
    navbar_items = [
      { title: "What's On",             path: events_path },
      { title: "About",                 children: get_navbar_children("about") },
      { title: "Get Involved",          children: get_navbar_children("get_involved") },
      { title: "Archives",              children: get_navbar_children("archives") },
      { title: "Contact",               path: static_path("contact") },
      { title: "Accessibility/Find Us", path: static_path("accessibility") }
    ]

    # Display the login link if the user is not signed in yet, otherwise display a link to the admin site and a link to log out.
    if user_signed_in?
      navbar_items << { title: "Members", path: admin_path }
      navbar_items << { title: "Log Out", path: destroy_user_session_path, method: :delete, item_class: "border border-white rounded-3" }
    else
      navbar_items << { title: "Log In", path: new_user_session_path, item_class: "border border-white rounded-3" }
    end

    navbar_items
  end

  def admin_navbar_items
    navbar_categories = []

    # Propose
    children = []
    children << { title: "Proposals", path: admin_proposals_calls_path, fa_icon: "fa-clipboard" } if can? :index, Admin::Proposals::Call
    children << { title: "Proposal Archive", path: archives_proposals_path, fa_icon: "fa-box-archive" } if can? :index, Admin::Proposals::Call
    navbar_categories << { title: "Propose", children: children, fa_icon: "fa-chalkboard" }

    # Productions
    children = []
    children << { title: "Events", path: admin_events_path, fa_icon: "fa-calendar" }             if can? :index, Event
    children << { title: "Shows", path: admin_shows_path, fa_icon: "fa-masks-theater" }          if can? :index, Show
    children << { title: "Workshops", path: admin_workshops_path, fa_icon: "fa-hammer" }         if can? :index, Workshop
    children << { title: "Festivals & Seasons", path: admin_seasons_path, fa_icon: "fa-shop" }   if can? :index, Season
    children << { title: "Questionnaires", path: admin_questionnaires_questionnaires_path, fa_icon: "fa-clipboard-list" } if can? :index, Admin::Questionnaires::Questionnaire
    children << { title: "Venues", path: admin_venues_path, fa_icon: "fa-building" }             if can? :index, Venue
    navbar_categories << { title: "Productions", children: children, fa_icon: "fa-industry" }

    # Staffing & Debt
    children = []
    children << { title: "Debt Admin", path: admin_debts_path, fa_icon: "fa-book-skull" }                     if can? :index, Admin::Debt
    children << { title: "Debt Notifications", path: admin_debt_notifications_path, fa_icon: "fa-receipt" }   if can? :index, Admin::DebtNotification
    children << { title: "Staffing", path: admin_staffings_path, fa_icon: "fa-people-group" }                 if can? :index, Admin::Staffing
    children << { title: "Staffing Debt", path: admin_staffing_debts_path, fa_icon: "fa-people-robbery" }     if can? :index, Admin::StaffingDebt
    children << { title: "Maintenance Credit", path: admin_maintenance_credits_path, fa_icon: "fa-broom" }  if can? :index, MaintenanceCredit
    children << { title: "Maintenance Sessions", path: admin_maintenance_sessions_path, fa_icon: "fa-hand-sparkles" }  if can? :index, MaintenanceSession
    children << { title: "Maintenance Debt", path: admin_maintenance_debts_path, fa_icon: "fa-wrench" }      if can? :index, Admin::MaintenanceDebt
    children << { title: "Debt Checker", path: new_admin_debt_checker_path, fa_icon: "fa-magnifying-glass-dollar" }  if can? :check_debt, Admin::Debt
    navbar_categories << { title: "Staffing & Debt", children: children, fa_icon: "fa-person" }

    # My Reimbursements — the producer/owner-facing surfaces (base access
    # permission). Kept out of the finance-only "Finance" category so a
    # producer who isn't on the finance team isn't shown a group called
    # "Finance" containing only their personal links.
    children = []
    # Points at /expenses, not the namespace root: the sidebar marks an item
    # active for its own page and anything beneath it, so the root would light
    # up for payment_details and my_budgets too. (An item that must match its
    # own page only can say `exact: true`.)
    children << { title: "My Claims", path: admin_reimbursements_expenses_path, fa_icon: "fa-file-invoice" }          if can? :access, :reimbursements
    children << { title: "Payment Details", path: edit_admin_reimbursements_payment_details_path, fa_icon: "fa-building-columns" } if can? :access, :reimbursements
    children << { title: "My Budgets", path: admin_reimbursements_my_budgets_path, fa_icon: "fa-user-check" } if can? :access, :reimbursements
    navbar_categories << { title: "My Reimbursements", children: children, fa_icon: "fa-receipt" }

    # Finance — the finance-team-only reimbursements tooling, in the order the
    # work is actually done rather than the order the screens were built.
    #
    # Fifteen flat links put the four WEEKLY items at positions 1, 2, 9 and 10,
    # with annual setup wedged between them, so +group:+ breaks them into the
    # four jobs: pay the claims, watch the budgets, keep the EUSA ledger true,
    # set the thing up. The renames are the audit's: "Expenses" collided with
    # the producer's own "My Claims", "History" named no subject, and
    # "Settings" is really the cost centres.
    children = []
    if can? :manage, :reimbursements_finance
      # Ungrouped, above the four job groups, because it is not one of the four
      # jobs — it is where you find out which of them is waiting on you. Needs
      # `exact: true`: it points at the namespace root, and the sidebar marks an
      # item active for its own page AND anything beneath it, so without it
      # every finance screen would light this up alongside its own entry.
      children << { title: "Finance home", path: admin_reimbursements_root_path, fa_icon: "fa-house", exact: true }

      children << { group: "Pay claims", title: "Review claims", path: admin_reimbursements_review_path, fa_icon: "fa-clipboard-check" }
      children << { group: "Pay claims", title: "All claims", path: admin_reimbursements_expense_edits_path, fa_icon: "fa-pen-to-square" }
      children << { group: "Pay claims", title: "Build batch", path: new_admin_reimbursements_batch_path, fa_icon: "fa-file-export" }
      children << { group: "Pay claims", title: "Batches", path: admin_reimbursements_batches_path, fa_icon: "fa-clock-rotate-left" }

      children << { group: "Budgets", title: "Budgets", path: admin_reimbursements_budgets_path, fa_icon: "fa-sack-dollar" }
      children << { group: "Budgets", title: "Overview", path: overview_admin_reimbursements_budgets_path, fa_icon: "fa-chart-pie" }
      children << { group: "Budgets", title: "Areas", path: admin_reimbursements_areas_path, fa_icon: "fa-diagram-project" }
      children << { group: "Budgets", title: "Forecast revisions", path: admin_reimbursements_budget_updates_path, fa_icon: "fa-calendar-plus" }

      children << { group: "EUSA ledger", title: "Reconcile", path: admin_reimbursements_reconciliation_path, fa_icon: "fa-scale-balanced" }
      children << { group: "EUSA ledger", title: "Ledger", path: admin_reimbursements_actuals_path, fa_icon: "fa-table-list" }
      children << { group: "EUSA ledger", title: "Export workbook", path: admin_reimbursements_export_path, fa_icon: "fa-file-excel" }

      children << { group: "Setup", title: "People", path: admin_reimbursements_people_path, fa_icon: "fa-address-book" }
      children << { group: "Setup", title: "Financial years", path: admin_reimbursements_financial_years_path, fa_icon: "fa-calendar-days" }
      children << { group: "Setup", title: "Cost centres", path: admin_reimbursements_settings_path, fa_icon: "fa-gear" }
      children << { group: "Setup", title: "Email & integrations", path: admin_reimbursements_status_path, fa_icon: "fa-heart-pulse" }
    end
    navbar_categories << { title: "Finance", children: children, fa_icon: "fa-money-bill-wave" }

    # Building — the crypt climate monitor. ONE entry: Sensors is reached by a
    # button on the dashboard rather than the sidebar. Adding it here would need
    # `exact: true` on this entry, or /admin/climate would light up alongside it.
    children = []
    children << { title: "Crypt Climate", path: admin_climate_dashboard_path, fa_icon: "fa-droplet" } if can? :read, :climate
    navbar_categories << { title: "Building", children: children, fa_icon: "fa-building-columns" }

    # Opportunities
    children = []
    children << { title: "Opportunities", path: admin_opportunities_path, fa_icon: "fa-lightbulb" }                                    if can? :index, Opportunity
    # Companies are publicly readable (for filtering), so gate this on the ability to manage them.
    children << { title: "Companies", path: admin_companies_path, fa_icon: "fa-building" }                                            if can? :create, Company
    children << { title: "Departments", path: admin_departments_path, fa_icon: "fa-sitemap" }                                         if can? :create, Department
    children << { title: "Marketing Creatives", path: admin_marketing_creatives_categories_path, fa_icon: "fa-wand-magic-sparkles" }             if can? :index, MarketingCreatives::Category
    children << { title: "Marketing Creatives Profile List", path: admin_marketing_creatives_profiles_path, fa_icon: "fa-users-rectangle" }  if can? :index, MarketingCreatives::Profile

    navbar_categories << { title: "Opportunities", children: children, fa_icon: "fa-lightbulb" }

    # Archives
    children = []
    children << { title: "Event Tags", path: admin_event_tags_path, fa_icon: "fa-calendar-week" }            if can? :index, EventTag
    children << { title: "Attachments", path: admin_attachments_path, fa_icon: "fa-paperclip" }          if can? :index, Attachment
    children << { title: "Attachment Tags", path: admin_attachment_tags_path, fa_icon: "fa-rectangle-list" }  if can? :index, AttachmentTag
    children << { title: "Pictures", path: admin_pictures_path, fa_icon: "fa-photo-film" }                if can? :index, Picture
    children << { title: "Picture Tags", path: admin_picture_tags_path, fa_icon: "fa-sliders" }        if can? :index, PictureTag
    children << { title: "Reviews", path: admin_reviews_path, fa_icon: "fa-newspaper" } if can? :index, Review
    navbar_categories << { title: "Archives", children: children, fa_icon: "fa-book-bookmark" }

    # Website Admin
    children = []
    children << { title: "Editable Blocks", path: admin_editable_blocks_path, fa_icon: "fa-pen-to-square" }  if can? :index, Admin::EditableBlock
    children << { title: "Carousel Items", path: admin_carousel_items_path, fa_icon: "fa-camera-rotate" }   if can? :index, CarouselItem
    children << { title: "Roles", path: admin_roles_path, fa_icon: "fa-id-card" }                      if can? :index, Role
    children << { title: "Permissions", path: admin_permissions_path, fa_icon: "fa-unlock" }          if can? :index, Admin::Permission
    children << { title: "Jobs", path: admin_mission_control_jobs_path, fa_icon: "fa-user-tie" }               if can? :manage, :jobs
    children << { title: "Test", path: admin_tests_path, fa_icon: "fa-vial" }                             if can? :manage, :tests
    navbar_categories << { title: "Website Admin", children: children, fa_icon: "fa-laptop-code" }

    # Users
    children = []
    children << { title: "Users", path: admin_users_path, fa_icon: "fa-circle-user" }                      if can? :index, User
    children << { title: "Activate Members", path: activate_admin_users_path, fa_icon: "fa-circle-check" } if can? :create, User
    children << { title: "Techies", path: admin_techies_path, fa_icon: "fa-toolbox" }                  if can? :index, Techie
    children << { title: "Duplicates", path: admin_duplicates_path, fa_icon: "fa-code-merge" } if can? :index, :duplicates
    navbar_categories << { title: "Users", children: children, fa_icon: "fa-circle-user" }

    # Apps
    children = []
    children << { title: "OAuth", path: oauth_applications_path, fa_icon: "fa-person-circle-question" } if can? :index, Doorkeeper::Application
    navbar_categories << { title: "Apps", children: children, fa_icon: "fa-square-envelope" }

    # Welfare Contact
    children = []
    children << { title: "Complaints Overview", path: admin_complaints_path, fa_icon: "fa-face-frown" } if can? :index, Complaint
    navbar_categories << { title: "Welfare Contact", children: children, fa_icon: "fa-user-doctor" }

    # Remove categories that do not have any children.
    navbar_categories.reject! { |category| category[:children].empty? }

    # Add logout as a standalone item
    navbar_categories << { title: "Log Out", path: destroy_user_session_path, method: :delete, fa_icon: "fa-right-from-bracket", is_logout: true }

    navbar_categories
  end
end
