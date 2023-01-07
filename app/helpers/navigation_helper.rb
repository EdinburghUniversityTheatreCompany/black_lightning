module NavigationHelper
  def public_navbar_items
    navbar_items = [
      { title: "What's On",             path: events_path },
      { title: 'About',                 children: get_navbar_children('about') },
      { title: 'Get Involved',          children: get_navbar_children('get_involved') },
      { title: 'Archives',              children: get_navbar_children('archives') },
      { title: 'Contact',               path: static_path('contact') },
      { title: 'Accessibility/Find Us', path: static_path('accessibility') }
    ]

    # Display the login link if the user is not signed in yet, otherwise display a link to the admin site and a link to log out.
    if user_signed_in?
      navbar_items << { title: 'Members', path: admin_path }
      navbar_items << { title: 'Log Out', path: destroy_user_session_path, method: :delete, item_class: 'border border-white rounded-3' }
    else
      navbar_items << { title: 'Log In', path: new_user_session_path, item_class: 'border border-white rounded-3' }
    end

    return navbar_items
  end

  def admin_navbar_items
    navbar_categories = []

    # Propose
    children = []
    children << { title: 'Proposals', path: admin_proposals_calls_path, fa_icon: 'fa-clipboard' } if can? :index, Admin::Proposals::Call
    children << { title: 'Proposal Archive', path: archives_proposals_path, fa_icon: 'fa-box-archive' } if can? :index, Admin::Proposals::Call
    navbar_categories << { title: 'Propose', children: children, fa_icon: 'fa-chalkboard' }

    # Productions
    children = []
    children << { title: 'Events', path: admin_events_path, fa_icon: 'fa-calendar' }             if can? :index, Event
    children << { title: 'Shows', path: admin_shows_path, fa_icon: 'fa-theater-masks' }          if can? :index, Show
    children << { title: 'Workshops', path: admin_workshops_path, fa_icon: 'fa-hammer' }         if can? :index, Workshop
    children << { title: 'Festivals & Seasons', path: admin_seasons_path, fa_icon: 'fa-shop' }   if can? :index, Season
    children << { title: 'Questionnaires', path: admin_questionnaires_questionnaires_path, fa_icon: 'fa-clipboard-list' } if can? :index, Admin::Questionnaires::Questionnaire
    children << { title: 'Venues', path: admin_venues_path, fa_icon: 'fa-building' }             if can? :index, Venue
    navbar_categories << { title: 'Productions', children: children, fa_icon: 'fa-industry' }

    # Staffing & Debt
    children = []
    children << { title: 'Debt Admin', path: admin_debts_path, fa_icon: 'fa-book-skull' }                     if can? :index, Admin::Debt
    children << { title: 'Debt Notifications', path: admin_debt_notifications_path, fa_icon: 'fa-receipt' }   if can? :index, Admin::DebtNotification
    children << { title: 'Staffing', path: admin_staffings_path, fa_icon: 'fa-people-group' }                 if can? :index, Admin::Staffing
    children << { title: 'Staffing Debt', path: admin_staffing_debts_path, fa_icon: 'fa-people-robbery' }     if can? :index, Admin::StaffingDebt
    children << { title: 'Maintenance Debt', path: admin_maintenance_debts_path, fa_icon: 'fa-wrench' }      if can? :index, Admin::MaintenanceDebt
    navbar_categories << { title: 'Staffing & Debt', children: children, fa_icon: 'fa-person' }

    # Opportunities
    children = []
    children << { title: 'Opportunities', path: admin_opportunities_path, fa_icon: 'fa-lightbulb' }                                    if can? :index, Opportunity
    children << { title: 'Marketing Creatives', path: admin_marketing_creatives_categories_path, fa_icon: 'fa-wand-magic-sparkles' }             if can? :index, MarketingCreatives::Category
    children << { title: 'Marketing Creatives Profile List', path: admin_marketing_creatives_profiles_path, fa_icon: 'fa-users-rectangle' }  if can? :index, MarketingCreatives::Profile

    navbar_categories << { title: 'Opportunities', children: children, fa_icon: 'fa-lightbulb' }

    # Archives
    children = []
    children << { title: 'Event Tags', path: admin_event_tags_path, fa_icon: 'fa-calendar-week' }            if can? :index, EventTag
    children << { title: 'Attachments', path: admin_attachments_path, fa_icon: 'fa-paperclip' }          if can? :index, Attachment
    children << { title: 'Attachment Tags', path: admin_attachment_tags_path, fa_icon: 'fa-rectangle-list' }  if can? :index, AttachmentTag
    children << { title: 'Pictures', path: admin_pictures_path, fa_icon: 'fa-photo-film' }                if can? :index, Picture
    children << { title: 'Picture Tags', path: admin_picture_tags_path, fa_icon: 'fa-sliders' }        if can? :index, PictureTag
    navbar_categories << { title: 'Archives', children: children, fa_icon: 'fa-book-bookmark' }

    # Website Admin
    children = []
    children << { title: 'Editable Blocks', path: admin_editable_blocks_path, fa_icon: 'fa-pen-to-square' }  if can? :index, Admin::EditableBlock
    children << { title: 'Carousel Items', path: admin_carousel_items_path, fa_icon: 'fa-camera-rotate' }   if can? :index, CarouselItem
    children << { title: 'Roles', path: admin_roles_path, fa_icon: 'fa-id-card' }                      if can? :index, Role
    children << { title: 'Permissions', path: admin_permissions_path, fa_icon: 'fa-unlock' }          if can? :index, Admin::Permission
    children << { title: 'Jobs', path: admin_jobs_overview_path, fa_icon: 'fa-user-tie' }               if can? :manage, :jobs
    navbar_categories << { title: 'Website Admin', children: children, fa_icon: 'fa-laptop-code' }

    # Users
    children = []
    children << { title: 'Users', path: admin_users_path, fa_icon: 'fa-circle-user' }                      if can? :index, User
    children << { title: 'Membership Activation', path: new_admin_membership_activation_token_path, fa_icon: 'fa-circle-check' } if can? :create, MembershipActivationToken
    children << { title: 'Techies', path: admin_techies_path, fa_icon: 'fa-toolbox' }                  if can? :index, Techie
    navbar_categories << { title: 'Users', children: children, fa_icon: 'fa-circle-user' }

    # Apps
    children = []
    children << { title: 'OAuth', path: oauth_applications_path, fa_icon: 'fa-person-circle-question' } if can? :index, Doorkeeper::Application
    navbar_categories << { title: 'Apps', children: children, fa_icon: 'fa-square-envelope' }

    # Welfare Contact
    children = []
    children << { title: 'Complaints Overview', path: admin_complaints_path, fa_icon: 'fa-face-frown' } if can? :index, Complaint
    navbar_categories << { title: 'Welfare Contact', children: children, fa_icon: 'fa-user-doctor' }

    # Remove categories that do not have any children.
    navbar_categories.reject! { |category| category[:children].empty? }
    
    return navbar_categories
  end
end
