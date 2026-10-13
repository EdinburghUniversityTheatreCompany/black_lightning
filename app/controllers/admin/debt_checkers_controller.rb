# frozen_string_literal: true

# Shows the debt and membership status of a pasted list of people, matched with UserImport.
# Read-only: creates and modifies nothing.
class Admin::DebtCheckersController < AdminController
  include Importable

  before_action { authorize! :check_debt, Admin::Debt }

  def new
    @title = "Debt Checker"
  end

  def show
    @user = User.find(params[:id])
    @title = "Debt Check: #{@user.name_or_email}"
  end

  def lookup
    user_id = params.dig(:debt_checker, :user_id) || params[:user_id]
    if user_id.present?
      redirect_to admin_debt_checker_path(user_id)
    else
      redirect_to new_admin_debt_checker_path, alert: "Please select a user"
    end
  end

  def preview
    data, input_type = parse_import_params

    if data.blank?
      helpers.append_to_flash(:error, "Please paste data or upload a file")
      redirect_to new_admin_debt_checker_path
      return
    end

    @import = UserImport.new(data, input_type: input_type, import_mode: :user)

    unless @import.valid?
      helpers.append_to_flash(:error, @import.errors.join(", "))
      redirect_to new_admin_debt_checker_path
      return
    end

    build_results(@import)

    @title = "Debt Check Results"
  end

  private

  def build_results(import)
    categorized = import.categorized
    @exact_matches = categorized[:exact_match_id].map { |item| exact_match(item, UserImport::MATCH_TYPE_LABELS.fetch(item[:match_type])) } +
                     categorized[:exact_match_email].map { |item| exact_match(item, "Email") }
    @fuzzy_matches = categorized[:fuzzy_match]
    @unmatched = categorized[:create_new].pluck(:row)

    users = User.where(id: @exact_matches.map { |m| m[:user].id } + @fuzzy_matches.flat_map { |m| m[:existing_users].map(&:id) })
    @in_debt_ids = users.in_debt.pluck(:id).to_set
    @member_ids = users.with_role(:member).pluck(:id).to_set
  end

  def exact_match(item, match_type)
    { row: item[:row], user: item[:existing_user], match_type: match_type }
  end
end
