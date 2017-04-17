##
# == Schema Information
#
# Table name: events
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *name*::               <tt>string(255)</tt>
# *tagline*::            <tt>string(255)</tt>
# *slug*::               <tt>string(255)</tt>
# *description*::        <tt>text</tt>
# *xts_id*::             <tt>integer</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
# *is_public*::          <tt>boolean</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *start_date*::         <tt>date</tt>
# *end_date*::           <tt>date</tt>
# *venue_id*::           <tt>integer</tt>
# *season_id*::          <tt>integer</tt>
# *author*::             <tt>string(255)</tt>
# *type*::               <tt>string(255)</tt>
#--
# == Schema Information End
#++
##
class Show < Event
  has_many :reviews, dependent: :destroy
  has_many :feedbacks, class_name: 'Admin::Feedback', dependent: :destroy
  has_many :questionnaires, class_name: 'Admin::Questionnaires::Questionnaire', dependent: :destroy

  attr_accessible :reviews, :reviews_attributes, :maintenance_debt_start, :staffing_debt_start

  accepts_nested_attributes_for :reviews, reject_if: :all_blank, allow_destroy: true

  def create_questionnaire(name)
    questionnaire = Admin::Questionnaires::Questionnaire.new
    questionnaire.show = self
    questionnaire.name = name
    questionnaire.save!
  end

  def create_mdebts
    uniqueTeam = self.users.uniq
    uniqueTeam.each do |usr,index|
      debt = Admin::MaintenanceDebt.new
      debt.show = self
      debt.user = usr
      debt.due_by = self.maintenance_debt_start
      debt.save
    end
  end

  def create_sdebts(numEach)
    uniqueTeam = self.users.uniq
    uniqueTeam.each do |usr|
      x = numEach - usr.admin_staffing_debts.where(converted:false).count
      x.times do |i|
        debt = Admin::StaffingDebt.new
        debt.show = self
        debt.user = usr
        debt.due_by = self.staffing_debt_start
        debt.converted = false
        debt.save!
      end
    end
  end

  def as_json(options = {})
    defaults = {
      include: [
        :reviews
      ]
    }

    options = options.merge(defaults) do |_key, oldval, newval|
      # http://stackoverflow.com/a/11171921
      (newval.is_a?(Array) ? (oldval + newval) : (oldval << newval)).uniq
    end

    super(options)
  end
end
