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
    super

    @admin_site = true
  end

  def set_navbar
    @navbar_categories = []

    # Propose
    children = []
    children << { title: 'Proposals', path: admin_proposals_calls_path, fa_icon: 'fa-clipboard' } if can? :index, Admin::Proposals::Call
    @navbar_categories << { title: 'Propose', children: children, fa_icon: 'fa-chalkboard' }

    # Productions
    children = []
    children << { title: 'Events', path: admin_events_path, fa_icon: 'fa-calendar' }             if can? :index, Event
    children << { title: 'Shows', path: admin_shows_path, fa_icon: 'fa-theater-masks' }          if can? :index, Show
    children << { title: 'Workshops', path: admin_workshops_path, fa_icon: 'fa-hammer' }         if can? :index, Workshop
    children << { title: 'Questionnaires', path: admin_questionnaires_questionnaires_path, fa_icon: 'fa-clipboard-list' } if can? :index, Admin::Questionnaires::Questionnaire
    children << { title: 'Venues', path: admin_venues_path, fa_icon: 'fa-building' }             if can? :index, Venue
    children << { title: 'Festivals & Seasons', path: admin_seasons_path, fa_icon: 'fa-shop' }   if can? :index, Season
    @navbar_categories << { title: 'Productions', children: children, fa_icon: 'fa-industry' }

    # Staffing & Debt
    children = []
    children << { title: 'Debt Admin', path: admin_debts_path, fa_icon: 'fa-book-skull' }                     if can? :index, Admin::Debt
    children << { title: 'Debt Notifications', path: admin_debt_notifications_path, fa_icon: 'fa-receipt' }   if can? :index, Admin::DebtNotification
    children << { title: 'Staffing', path: admin_staffings_path, fa_icon: 'fa-people-group' }                 if can? :index, Admin::Staffing
    children << { title: 'Staffing Debt', path: admin_staffing_debts_path, fa_icon: 'fa-people-robbery' }     if can? :index, Admin::StaffingDebt
    children << { title: 'Maintenance Debt', path: admin_maintenance_debts_path, fa_icon: 'fa-toolbox' }      if can? :index, Admin::MaintenanceDebt
    @navbar_categories << { title: 'Staffing & Debt', children: children, fa_icon: 'fa-person' }

    # Opportunities
    children = []
    children << { title: 'Opportunities', path: admin_opportunities_path, fa_icon: 'fa-info' }                                    if can? :index, Opportunity
    children << { title: 'Marketing Creatives', path: admin_marketing_creatives_categories_path, fa_icon: 'fa-info' }             if can? :index, MarketingCreatives::Category
    children << { title: 'Marketing Creatives Profile List', path: admin_marketing_creatives_profiles_path, fa_icon: 'fa-info' }  if can? :index, MarketingCreatives::Profile

    @navbar_categories << { title: 'Opportunities', children: children, fa_icon: 'fa-info' }

    # Archives
    children = []
    children << { title: 'Event Tags', path: admin_event_tags_path, fa_icon: 'fa-info' }            if can? :index, EventTag
    children << { title: 'Attachments', path: admin_attachments_path, fa_icon: 'fa-info' }          if can? :index, Attachment
    children << { title: 'Attachment Tags', path: admin_attachment_tags_path, fa_icon: 'fa-info' }  if can? :index, AttachmentTag
    children << { title: 'Pictures', path: admin_pictures_path, fa_icon: 'fa-info' }                if can? :index, Picture
    children << { title: 'Picture Tags', path: admin_picture_tags_path, fa_icon: 'fa-info' }        if can? :index, PictureTag
    @navbar_categories << { title: 'Archives', children: children, fa_icon: 'fa-info' }

    # Website Admin
    children = []
    children << { title: 'Editable Blocks', path: admin_editable_blocks_path, fa_icon: 'fa-info' }  if can? :index, Admin::EditableBlock
    children << { title: 'Carousel Items', path: admin_carousel_items_path, fa_icon: 'fa-info' }   if can? :index, CarouselItem
    children << { title: 'Roles', path: admin_roles_path, fa_icon: 'fa-info' }                      if can? :index, Role
    children << { title: 'Permissions', path: admin_permissions_path, fa_icon: 'fa-info' }          if can? :index, Admin::Permission
    children << { title: 'Jobs', path: admin_jobs_overview_path, fa_icon: 'fa-info' }               if can? :manage, :jobs
    @navbar_categories << { title: 'Website Admin', children: children, fa_icon: 'fa-info' }

    # Users
    children = []
    children << { title: 'Users', path: admin_users_path, fa_icon: 'fa-info' }                      if can? :index, User
    children << { title: 'Membership Activation', path: new_admin_membership_activation_token_path, fa_icon: 'fa-info' } if can? :create, MembershipActivationToken
    children << { title: 'Techies', path: admin_techies_path, fa_icon: 'fa-info' }                  if can? :index, Techie

    @navbar_categories << { title: 'Users', children: children, fa_icon: 'fa-info' }

    # Apps
    children = []
    children << { title: 'OAuth', path: oauth_applications_path, fa_icon: 'fa-info' } if can? :index, Doorkeeper::Application

    @navbar_categories << { title: 'Apps', children: children, fa_icon: 'fa-info' }

    # Welfare Contact
    children = []
    children << { title: 'Complaints Overview', path: admin_complaints_path, fa_icon: 'fa-info' } if can? :index, Complaint

    @navbar_categories << { title: 'Welfare Contact', children: children, fa_icon: 'fa-info' }

    @navbar_categories.reject! { |category| category[:children].empty? }

    # to do - unsorted things

    add_breadcrumb 'Home', :admin_path

  
    path_array = @current_path.split("/")[2..-1]
    full_working_path = "/admin"

    if path_array.is_a? Array
      path_array.each do |working_path|
        current_path_title = working_path.gsub(Regexp.union('_'), ' ')
        current_path_title = working_path.titleize
        full_working_path += "/"+working_path

        add_breadcrumb current_path_title, full_working_path
      end
    elsif path_array.is_a? String
      path_title = path_array.gsub(Regexp.union('_'), ' ')
      path_title = path_title.titleize

      add_breadcrumb path_title, @current_path
    end
  end
end
