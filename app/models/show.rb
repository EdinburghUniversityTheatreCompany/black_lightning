##
# == Schema Information
#
# Table name: events
#
# *id*::                     <tt>integer, not null, primary key</tt>
# *name*::                   <tt>string(255)</tt>
# *tagline*::                <tt>string(255)</tt>
# *slug*::                   <tt>string(255)</tt>
# *publicity_text*::         <tt>text(65535)</tt>
# *members_only_text*::      <tt>text(65535)</tt>
# *xts_id*::                 <tt>integer</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
# *is_public*::              <tt>boolean</tt>
# *image_file_name*::        <tt>string(255)</tt>
# *image_content_type*::     <tt>string(255)</tt>
# *image_file_size*::        <tt>integer</tt>
# *image_updated_at*::       <tt>datetime</tt>
# *start_date*::             <tt>date</tt>
# *end_date*::               <tt>date</tt>
# *venue_id*::               <tt>integer</tt>
# *season_id*::              <tt>integer</tt>
# *author*::                 <tt>string(255)</tt>
# *type*::                   <tt>string(255)</tt>
# *price*::                  <tt>string(255)</tt>
# *spark_seat_slug*::        <tt>string(255)</tt>
# *maintenance_debt_start*:: <tt>date</tt>
# *staffing_debt_start*::    <tt>date</tt>
# *proposal_id*::            <tt>integer</tt>
#--
# == Schema Information End
#++

class Show < Event
  include ApplicationHelper
  include AcademicYearHelper

  before_save :normalize_debt_amounts

  validates :author, :price, presence: true

  # Validate uniqueness on Event Subtype basis instead of on the event.
  # Otherwise, you cannot have two different types with the same slug.
  validates :slug, uniqueness: { case_sensitive: false }

  has_many :feedbacks, class_name: "Admin::Feedback", dependent: :restrict_with_error

  def self.ransackable_associations(auth_object = nil)
    super
  end

  # If you add more fields, you might need to add to this.
  # This is to prevent data loss from occuring when converting a Show into another type of event.
  # Please also modify the error messagse in admin Show controller that is displayed when this returns false
  # and the confirm message on the admin Shows show page for converting.
  def can_convert?
    feedbacks.empty?
  end

  def debt_configuration_active?
    maintenance_debt_amount.present? || staffing_debt_amount.present?
  end

  def tag_debt_recommendations
    @tag_debt_recommendations ||= event_tags.where.not(recommended_maintenance_debts: nil)
              .or(event_tags.where.not(recommended_staffing_debts: nil))
              .map do |tag|
      {
        tag_name: tag.name,
        maintenance: tag.recommended_maintenance_debts,
        staffing: tag.recommended_staffing_debts
      }
    end
  end

  def matches_tag_debt_recommendations?
    tag_debt_recommendations.any? do |rec|
      maintenance_debt_amount == rec[:maintenance] &&
      staffing_debt_amount == rec[:staffing]
    end
  end

  def debt_recommendation_status
    recs = tag_debt_recommendations
    return :no_recommendation if recs.empty?
    return :needs_config unless debt_configuration_active?
    return :matches if matches_tag_debt_recommendations?
    :mismatch
  end

  def sync_debts_for_all_users
    return { maintenance: 0, staffing: 0 } unless debt_configuration_active?
    return { maintenance: 0, staffing: 0 } unless end_date && end_date > start_of_year

    totals = { maintenance: 0, staffing: 0 }

    team_members.includes(:user).find_each do |team_member|
      result = sync_debts_for_team_member(team_member)
      totals[:maintenance] += result[:maintenance]
      totals[:staffing] += result[:staffing]
    end

    totals
  end

  def sync_debts_for_user(user)
    return { maintenance: 0, staffing: 0 } unless debt_configuration_active?
    return { maintenance: 0, staffing: 0 } unless end_date && end_date > start_of_year

    team_member = team_members.find_by(user: user)
    return { maintenance: 0, staffing: 0 } unless team_member

    sync_debts_for_team_member(team_member)
  end

  def as_json(options = {})
    defaults = {
      include: [
          :reviews
      ]
    }

    options = merge_hash(defaults, options)

    super(options)
  end

  private

  def normalize_debt_amounts
    self.maintenance_debt_amount = nil if maintenance_debt_amount == 0
    self.staffing_debt_amount = nil if staffing_debt_amount == 0
  end

  def sync_debts_for_team_member(team_member)
    user = team_member.user
    created = { maintenance: 0, staffing: 0 }

    if maintenance_debt_amount.present? && maintenance_debt_start.present?
      existing = user.admin_maintenance_debts.where(show: self).count
      needed = maintenance_debt_amount - existing

      needed.times do
        Admin::MaintenanceDebt.create!(
          show: self,
          user: user,
          due_by: maintenance_debt_start,
          state: :normal,
          converted_from_staffing_debt: false
        )
        created[:maintenance] += 1
      end
    end

    if staffing_debt_amount.present? && staffing_debt_start.present?
      existing = user.admin_staffing_debts.where(show: self).count
      amount = staffing_debt_amount_for_position(team_member.position, staffing_debt_amount)
      needed = amount - existing

      needed.times do
        Admin::StaffingDebt.create!(
          show: self,
          user: user,
          due_by: staffing_debt_start,
          state: :normal,
          converted_from_maintenance_debt: false
        )
        created[:staffing] += 1
      end
    end

    created
  end

  def staffing_debt_amount_for_position(position, base_amount)
    roles = position.split("/").map(&:strip)

    # Welfare only if it's their ONLY role
    return 0 if roles.length == 1 && roles.first.downcase.include?("welfare")

    # Assistant cap only if ALL roles are assistant roles
    if roles.all? { |role| role.downcase.include?("assistant") }
      return [ base_amount, 1 ].min
    end

    base_amount
  end
end
