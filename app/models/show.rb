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
  
  validates :author, :price, presence: true

  # Validate uniqueness on Event Subtype basis instead of on the event.
  # Otherwise, you cannot have two different types with the same slug.
  validates :slug, uniqueness: { case_sensitive: false }

  has_many :feedbacks, class_name: 'Admin::Feedback', dependent: :restrict_with_error

  def self.ransackable_associations(auth_object = nil)
    super
  end

  # If you add more fields, you might need to add to this.
  # This is to prevent data loss from occuring when converting a Show into another type of event.
  # Please also modify the error messagse in admin Show controller that is displayed when this returns false
  # and the confirm message on the admin Shows show page for converting.
  def can_convert?
    return feedbacks.empty?
  end

  def create_maintenance_debts
    users.select(:id, :position, :last_name).distinct.each do |user|
      debts = user.admin_maintenance_debts.where(show_id: id, converted_from_staffing_debt: false)

      # If there is no maintenance debt for this show yet, create one.
      if debts.empty?
        Admin::MaintenanceDebt.create!(
          show: self,
          user: user,
          due_by: maintenance_debt_start,
          state: :normal,
          converted_from_staffing_debt: false
        )
      # If there is, just update the due_by date.
      else
        debts.update_all(due_by: maintenance_debt_start)
      end 
    end
  end

  def create_staffing_debts(total_amount)
    users.select(:id, :position, :last_name).distinct.each do |user|
      # Debts converted from a maintenance debt should not count towards the staffing debt total for a show.
      # If someone should get two staffing debts, and they have had their maintenance debt converted, they should get
      # a total of 3 debts. If you included the converted maintenance_debt here, adding the staffing debts would only add 
      # one, for a total of 2.
      amount = total_amount - user.admin_staffing_debts.where(show_id: id, converted_from_maintenance_debt: false).count
      
      amount.times do
        Admin::StaffingDebt.create!(
          show: self,
          user: user,
          due_by: staffing_debt_start,
          state: :normal,
          converted_from_maintenance_debt:false
        )
      end
    end
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
end
