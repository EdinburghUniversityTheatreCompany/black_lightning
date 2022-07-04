class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_backend!
  before_action :check_consented!, if: :user_signed_in?

  layout 'admin'

  private

  def authorize_backend!
    authorize! :access, :backend
  end

  # Check if the user has consented before every request.
  def check_consented!
    return if current_user.consented?

    exception = CanCan::AccessDenied.new(t('errors.not_consented'))

    render_error_page(exception, 'errors/not_consented', 403)
    return false
  end

  def set_globals
    @navbar_categories = []

    # Propose
    children =[]
    children << { title: 'Proposals', path: admin_proposals_calls_path, fa_icon: "fa-info"} if can? :index, Admin::Proposals::Call
    @navbar_categories << {title: 'Propose', children: children, fa_icon: "fa-info"}

    # Productions
    children =[]
    children << { title: 'Events', path: admin_events_path, fa_icon: "fa-info"} if can? :index, Event
    children << { title: 'Shows', path: admin_shows_path, fa_icon: "fa-info"} if can? :index, Show
    children << { title: 'Workshops', path: admin_workshops_path, fa_icon: "fa-info"} if can? :index, Workshop
    children << { title: 'Questionnaires', path: admin_questionnaires_questionnaires_path, fa_icon: "fa-info"} if can? :index, Admin::Questionnaires::Questionnaire
    children << { title: 'Venues', path: admin_venues_path, fa_icon: "fa-info"} if can? :index, Venue
    children << { title: 'Festivals & Seasons', path: admin_seasons_path, fa_icon: "fa-info"} if can? :index, Season
    @navbar_categories << {title: 'Productions', children: children, fa_icon: "fa-info"}

    # Staffing & Debt
    children =[]
    children << { title: 'Debt Admin', path: admin_debts_path, fa_icon: "fa-info"} if can? :index, Admin::Debt
    children << { title: 'My Debts', path: admin_debts_path(current_user), fa_icon: "fa-info"} if can? :show, Admin::Debt 
    children << { title: 'Debt Notifications', path: admin_debt_notifications_path,  fa_icon: "fa-info"} if can? :index, Admin::DebtNotification
    children << { title: 'Proposals', path: admin_proposals_calls_path,  fa_icon: "fa-info"} if can? :index, Admin::Proposals::Call
    children << { title: 'Staffing', path: admin_staffings_path,  fa_icon: "fa-info"} if can? :index, Admin::Staffing
    children << { title: 'Staffing Debt', path: admin_staffing_debts_path,  fa_icon: "fa-info"} if can? :index, Admin::StaffingDebt
    children << { title: 'Maintenance Debt', path: admin_maintenance_debts_path,  fa_icon: "fa-info"} if can? :index, Admin::MaintenanceDebt
    @navbar_categories << {title: 'Staffing & Debt', children: children, fa_icon: "fa-info"}

    # Opportunities
    children =[]
    children << { title: 'Opportunities', path: admin_opportunities_path,  fa_icon: "fa-info"} if can? :index, Opportunity
    children << { title: 'Marketing Creatives', path: admin_marketing_creatives_categories_path,  fa_icon: "fa-info"} if can? :index, MarketingCreatives::Category
    children << { title: 'Marketing Creatives Profile List', path: admin_marketing_creatives_profiles_path,  fa_icon: "fa-info"} if can? :index, MarketingCreatives::Profile
    
    @navbar_categories << {title: 'Opportunities', children: children, fa_icon: "fa-info"}

    # Archives
    children =[]
    children << { title: 'Event Tags', path: admin_event_tags_path,  fa_icon: "fa-info"} if can? :index, EventTag
    children << { title: 'Attachments', path: admin_attachments_path,  fa_icon: "fa-info"} if can? :index, Attachment
    children << { title: 'Attachment Tags', path: admin_attachment_tags_path,  fa_icon: "fa-info"} if can? :index, AttachmentTag
    children << { title: 'Pictures', path: admin_pictures_path,  fa_icon: "fa-info"} if can? :index, Picture
    children << { title: 'Picture Tags', path: admin_picture_tags_path,  fa_icon: "fa-info"} if can? :index, PictureTag
    @navbar_categories << {title: 'Archives', children: children, fa_icon: "fa-info"}
    
    # Website Admin
    children =[]
    children << { title: 'Editable Blocks', path: admin_editable_blocks_path,  fa_icon: "fa-info"} if can? :index, Admin::EditableBlock
    children << { title: 'Roles', path: admin_roles_path,  fa_icon: "fa-info"} if can? :index, Role
    children << { title: 'Permissions', path: admin_permissions_path,  fa_icon: "fa-info"} if can? :index, Admin::Permission
    children << { title: 'Jobs', path: admin_jobs_overview_path,  fa_icon: "fa-info"} if can? :manage, :jobs
    @navbar_categories << {title: 'Website Admin', children: children, fa_icon: "fa-info"}

    # Users
    children =[]
    children << { title: 'Users', path: admin_users_path,  fa_icon: "fa-info"} if can? :index, User
    children << { title: 'Membership Activation', path: new_admin_membership_activation_token_path,  fa_icon: "fa-info"} if can? :create, MembershipActivationToken
    children << { title: 'Techies', path: admin_techies_path,  fa_icon: "fa-info"} if can? :index, Techie
   
    @navbar_categories << {title: 'Users', children: children, fa_icon: "fa-info"}

    # Apps
    children << { title: 'OAuth', path: oauth_applications_path,  fa_icon: "fa-info"} if can? :index, Doorkeeper::Application
    
    @navbar_categories << {title: 'Apps', children: children, fa_icon: "fa-info"}

    #@navbar_categories.reject! {|category| category.children.empty? }
# to do - unsorted things
  end
end
