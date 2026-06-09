##
# Controller for the get_involved pages.
#
# The pages are all defined as Editable Blocks.
##
class GetInvolvedController < ApplicationController
  skip_authorization_check only: [ :opportunities, :page ]

  def opportunities
    @q = Opportunity.listable.ransack(params[:q])
    # distinct: true dedups the rows the category filter's roles join can produce. EUTC-first sort
    # via #eutc_first orders on opportunities columns only, so it stays valid with DISTINCT.
    @opportunities = @q.result(distinct: true).eutc_first.includes(:company, :roles, :creator)

    @editable_block = Admin::EditableBlock.find_by(url: "get_involved/opportunities")

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def new
    @opportunity = Opportunity.new
    @opportunity.roles.build
    authorize! :create, Opportunity
  end

  def create
    authorize! :create, Opportunity

    # Build with a guard: this is a public endpoint, so a crafted invalid enum value would
    # otherwise raise ArgumentError. Treat it as a normal invalid submission.
    @opportunity = Opportunity.new(opportunity_params)
    @opportunity.creator = current_user if user_signed_in?
    @opportunity.company_name = params.dig(:opportunity, :company_name)  # kept so it survives re-render
    @opportunity.company = find_or_create_company
    @opportunity.approved = false

    # Silently drop bot submissions (honeypot filled) without saving, but log so a
    # false positive on a real user is at least observable.
    if honeypot_triggered?
      Rails.logger.info("Dropped opportunity submission: honeypot triggered")
      return redirect_to(get_involved_opportunities_path, notice: submission_notice)
    end

    # Logged-out submissions must pass reCAPTCHA (skipped in test/development).
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
  end

  private

  def opportunity_params
    permitted = [ :title, :description, :expiry_date, :email_visibility, :contact_email,
                  :project, :author, :apply_url, :compensation_type, :experience_level,
                  roles_attributes: [ :position, :category, :note, :_destroy ] ]
    # External (logged-out) submitters identify themselves; members are taken from current_user.
    permitted += [ :submitter_name, :submitter_email ] unless user_signed_in?

    params.require(:opportunity).permit(*permitted)
  end

  # Find or create the company named on the form. New companies default to external (not EUTC).
  def find_or_create_company
    name = @opportunity.company_name&.strip
    return if name.blank?

    company = Company.find_by("LOWER(name) = LOWER(?)", name) || Company.create(name: name)
    company if company.persisted?
  end

  # Re-render the submission form with a fresh role row if the user removed them all.
  def rerender_new
    @opportunity.roles.build if @opportunity.roles.empty?
    render :new, status: :unprocessable_entity
  end

  # Hidden field that real users leave empty; bots tend to fill it in.
  def honeypot_triggered?
    params.dig(:opportunity, :website_url).present?
  end

  def submission_notice
    "Opportunity submitted! It will appear once reviewed."
  end
end
