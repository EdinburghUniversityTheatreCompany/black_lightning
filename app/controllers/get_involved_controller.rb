##
# Controller for the get_involved pages.
#
# The pages are all defined as Editable Blocks.
##
class GetInvolvedController < ApplicationController
  include EditableBlockPage

  skip_authorization_check only: [ :opportunities, :page ]

  def opportunities
    @q = Opportunity.listable.ransack(params[:q])
    # distinct: true dedups the department filter's roles join; eutc_first stays valid with it.
    @opportunities = @q.result(distinct: true).eutc_first.includes(:company, :roles, :creator)

    @editable_block = Admin::EditableBlock.find_by(url: "get_involved/opportunities")

    set_meta_from_editable_block

    # Explicit, not block-derived: this page must win "theatre opportunities Edinburgh" whether or
    # not the editable block is written.
    @title = "Opportunities"
    @meta[:description] = "Auditions, crew calls and paid and unpaid theatre opportunities in Edinburgh, from the EUTC at Bedlam Theatre and other student and fringe companies."

    respond_to do |format|
      format.html
      # Only genuine live-search fetches (from live_search_controller) should get the
      # #index-results fragment — they always carry q[...] params. A Turbo form-submission redirect
      # (e.g. after #create) follows the 302 with the same turbo_stream Accept header but no q
      # params; answering it with the fragment would silently do nothing on the form page (which has
      # no #index-results element), so serve the full HTML page and let the flash + navigation show.
      format.turbo_stream do
        if params[:q].present?
          render
        else
          render :opportunities, formats: :html, content_type: "text/html"
        end
      end
    end
  end

  def new
    @opportunity = Opportunity.new
    @opportunity.roles.build
    authorize! :create, Opportunity

    set_submission_meta
  end

  def create
    authorize! :create, Opportunity

    # Build with a guard: this is a public endpoint, so a crafted invalid enum value would
    # otherwise raise ArgumentError. Treat it as a normal invalid submission.
    @opportunity = Opportunity.new(opportunity_params)
    @opportunity.creator = current_user if user_signed_in?
    @opportunity.approved = false

    # Logged so a false positive on a real user is observable.
    if honeypot_triggered?
      Rails.logger.info("Dropped opportunity submission: honeypot triggered")
      return redirect_to(get_involved_opportunities_path, notice: submission_notice)
    end

    unless user_signed_in? || verify_recaptcha(model: @opportunity, action: "submit_opportunity")
      return rerender_new
    end

    if @opportunity.save
      redirect_to get_involved_opportunities_path, notice: submission_notice
    else
      rerender_new
    end
  rescue ArgumentError
    @opportunity ||= Opportunity.new
    rerender_new
  end

  def page
    @editable_block = Admin::EditableBlock.find_by!(url: @current_path.delete_prefix("/"))

    set_meta_from_editable_block
  end

  private

  # Shared with rerender_new: a failed save re-renders :new without going through #new, which left
  # the page titled "Bedlam Theatre".
  def set_submission_meta
    @title = "Submit an Opportunity"
    @meta[:description] = "Post an audition, crew call or theatre opportunity to Bedlam Theatre's listings, open to any Edinburgh student or fringe company."
  end

  def opportunity_params
    permitted = [ :title, :description, :expiry_date, :email_visibility, :contact_email,
                  :company_name, :project, :author, :dates, :location, :apply_url, :compensation_type, :experience_level,
                  roles_attributes: [ :position, :department_name, :note, :_destroy ] ]
    # Submitter fields only when logged out; members are taken from current_user.
    permitted += [ :submitter_name, :submitter_email ] unless user_signed_in?

    params.require(:opportunity).permit(*permitted)
  end

  def rerender_new
    @opportunity.roles.build if @opportunity.roles.empty?
    set_submission_meta
    render :new, status: :unprocessable_entity
  end

  def honeypot_triggered?
    params.dig(:opportunity, :website_url).present?
  end

  def submission_notice
    "Opportunity submitted! It will appear once reviewed."
  end
end
