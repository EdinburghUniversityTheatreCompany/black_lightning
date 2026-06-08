##
# Controller for the get_involved pages.
#
# The pages are all defined as Editable Blocks.
##
class GetInvolvedController < ApplicationController
  skip_authorization_check only: [ :opportunities, :page ]
  before_action :authenticate_user!, only: [ :new, :create ]

  def opportunities
    @opportunities = Opportunity.active.includes(:company, :roles, :creator)

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

  def opportunity_params
    params.require(:opportunity).permit(:title, :description, :expiry_date, :email_visibility, :contact_email)
  end
end
