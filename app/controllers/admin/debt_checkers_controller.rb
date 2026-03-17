# frozen_string_literal: true

##
# Controller for bulk-checking debt status of a list of people.
# Read-only — does not create users or modify anything.
# Reuses UserImport matching logic to find users, then displays
# their debt and membership status.
##
class Admin::DebtCheckersController < AdminController
  include Importable

  def new
    authorize! :index, Admin::Debt
    @title = "Bulk Debt Checker"
  end

  def preview
    authorize! :index, Admin::Debt

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
    # Collect all matched users across buckets for bulk-loading debt info
    @exact_matches = []
    @fuzzy_matches = []
    @unmatched = []

    import.categorized[:exact_match_id].each do |item|
      @exact_matches << {
        row: item[:row],
        user: item[:existing_user],
        match_type: match_type_label(item[:match_type])
      }
    end

    import.categorized[:exact_match_email].each do |item|
      @exact_matches << {
        row: item[:row],
        user: item[:existing_user],
        match_type: "Email"
      }
    end

    import.categorized[:fuzzy_match].each do |item|
      @fuzzy_matches << {
        row: item[:row],
        candidates: item[:existing_users],
        years_active_cache: import.years_active_cache
      }
    end

    import.categorized[:create_new].each do |item|
      @unmatched << item[:row]
    end

    # Bulk-load debt status for all matched user IDs
    all_user_ids = @exact_matches.map { |m| m[:user].id } +
                   @fuzzy_matches.flat_map { |m| m[:candidates].map(&:id) }

    @in_debt_ids = if all_user_ids.any?
      User.where(id: all_user_ids).in_debt.pluck(:id).to_set
    else
      Set.new
    end

    @member_ids = if all_user_ids.any?
      User.where(id: all_user_ids).with_role(:member).pluck(:id).to_set
    else
      Set.new
    end

    @total_rows = import.rows.size
    @in_debt_count = @exact_matches.count { |m| @in_debt_ids.include?(m[:user].id) }
  end

  def match_type_label(match_type)
    case match_type
    when :user_id then "User ID"
    when :student_id then "Student ID"
    when :associate_id then "Associate ID"
    else match_type.to_s.titleize
    end
  end
end
