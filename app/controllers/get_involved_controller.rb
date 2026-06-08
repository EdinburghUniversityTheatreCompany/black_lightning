##
# Controller for the get_involved pages.
#
# The pages are all defined as Editable Blocks.
##
class GetInvolvedController < ApplicationController
  skip_authorization_check only: [ :opportunities, :page ]
  before_action :authenticate_user!, only: [ :new, :create ]

  def opportunities
    @q = Opportunity.listable.ransack(params[:q])
    # Always surface EUTC/internal opportunities first; users do not pick a sort.
    # (Depends on Company#internal being ransackable and :company being a ransackable association.)
    @q.sorts = [ "company_internal desc", "expiry_date asc" ] if @q.sorts.empty?
    filtered = @q.result

    # Tabs reflect the categories available within the current company/compensation/experience
    # filters (but before the category itself is applied), so switching category stays meaningful.
    @available_categories = available_categories_in(filtered)

    @selected_category = selected_category
    filtered = filtered.with_role_category(@selected_category) if @selected_category

    @opportunities = filtered.includes(:company, :roles, :creator)

    @editable_block = Admin::EditableBlock.find_by(url: "get_involved/opportunities")
  end

  def new
    @opportunity = Opportunity.new
    authorize! :create, Opportunity
  end

  def create
    @opportunity = Opportunity.new(opportunity_params)
    @opportunity.creator = current_user
    @opportunity.approved = false

    authorize! :create, Opportunity

    if @opportunity.save
      redirect_to get_involved_opportunities_path, notice: "Opportunity submitted! It will appear once reviewed."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def page
    @editable_block = Admin::EditableBlock.find_by!(url: @current_path.delete_prefix("/"))
  end

  private

  # The category tab the user picked, if it is a real category.
  def selected_category
    category = params[:category].presence
    category if category && OpportunityRole.categories.key?(category)
  end

  # Category keys present among the given opportunities, for the tabs.
  def available_categories_in(relation)
    # reorder(nil) drops the default :ordering sort, which would break GROUP BY under only_full_group_by.
    counts = OpportunityRole.reorder(nil)
                            .where(opportunity_id: relation.except(:order).select(:id))
                            .group(:category).count
    OpportunityRole.categories.keys.select { |key| counts[key].to_i.positive? }
  end

  def opportunity_params
    params.require(:opportunity).permit(:title, :description, :expiry_date, :email_visibility, :contact_email)
  end
end
