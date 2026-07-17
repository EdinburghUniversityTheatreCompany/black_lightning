# == Schema Information
#
# Table name: reimbursements_budgets
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  budget_type        :string(255)      default("Expense"), not null
#  initial_budget     :decimal(12, 2)
#  name               :string(255)      default(""), not null
#  nominal_code       :string(255)      default(""), not null
#  notes              :text(65535)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  airtable_record_id :string(255)
#  cost_centre_id     :bigint
#  financial_year_id  :bigint
#
# Indexes
#
#  index_reimbursements_budgets_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_reimbursements_budgets_on_cost_centre_id      (cost_centre_id)
#  index_reimbursements_budgets_on_financial_year_id   (financial_year_id)
#  index_reimbursements_budgets_on_nominal_code        (nominal_code)
#
# Foreign Keys
#
#  fk_rails_...  (cost_centre_id => reimbursements_cost_centres.id)
#  fk_rails_...  (financial_year_id => reimbursements_financial_years.id)
#
module Reimbursements
  ##
  # A budget category. ActiveRecord replacement for the Airtable-era PORO
  # (now Reimbursements::Airtable::Budget), same public interface.
  #
  # The Airtable rollups/formulas are computed here instead of loaded
  # (definitions confirmed from the base schema export — all amounts are
  # excl-VAT, mirroring the BACS spreadsheet):
  #
  #   committed_amount = Σ amount_excl_vat, status ∈ {Approved, Submitted, Paid}
  #   total_paid       = Σ amount_excl_vat, status = Paid
  #   current_forecast = latest forecast's amount (nil when none logged)
  #   remaining        = current_forecast − committed_amount (nil without forecast)
  #   variance         = current_forecast − initial_budget (nil without either)
  #
  # Each is memoized per instance — one Store lives per request, so a Review
  # render costs one query per figure, not one per card per figure.
  class Budget < ApplicationRecord
    TYPES = %w[Expense Income].freeze

    COMMITTED_STATUSES = [ Status::APPROVED, Status::SUBMITTED, Status::PAID ].freeze

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true
    has_many :expenses, class_name: "Reimbursements::Expense",
                        dependent: :nullify, inverse_of: :budget
    has_many :forecasts, class_name: "Reimbursements::BudgetForecast",
                         dependent: :destroy, inverse_of: :budget
    has_many :budget_ownerships, class_name: "Reimbursements::BudgetOwner",
                                 dependent: :destroy, inverse_of: :budget
    has_many :owners, through: :budget_ownerships, source: :person

    validates :name, presence: true
    validates :budget_type, inclusion: { in: TYPES }

    def record_id = id&.to_s

    # The PORO exposed owner links as an array of People record ids; OwnerReview
    # and the budgets UI compare them against person.record_id strings.
    def owner_ids
      owners.map(&:record_id)
    end

    def income? = budget_type == "Income"

    def committed_amount
      @committed_amount ||= expenses.where(status: COMMITTED_STATUSES).sum(:amount_excl_vat)
    end

    def total_paid
      @total_paid ||= expenses.where(status: Status::PAID).sum(:amount_excl_vat)
    end

    def current_forecast
      return @current_forecast if defined?(@current_forecast)

      @current_forecast = forecasts.order(date: :desc, id: :desc).first&.amount
    end

    # Nil when no forecast has been logged yet — callers treat nil as "not
    # tracked, don't block", exactly as the blank Airtable formula did.
    def remaining
      return nil if current_forecast.nil?

      current_forecast - committed_amount
    end

    def variance
      return nil if current_forecast.nil? || initial_budget.nil?

      current_forecast - initial_budget
    end

    # Genuinely overspent: nothing left against the current forecast/plan.
    # `remaining` already folds in forecast and committed, so the badge keys
    # off it alone. Income budgets are never over budget.
    def over_budget?
      return false if income?

      !remaining.nil? && remaining.negative?
    end

    # A softer state: committed or paid has passed the ORIGINAL initial figure,
    # but the forecast was revised up to cover it so there's still remaining.
    def over_initial_budget?
      return false if income? || over_budget?
      return true if initial_budget && committed_amount && committed_amount > initial_budget
      return true if initial_budget && total_paid && total_paid > initial_budget

      false
    end
  end
end
