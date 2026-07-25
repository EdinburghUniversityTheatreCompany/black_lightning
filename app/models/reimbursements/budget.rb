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
    include RecordId
    include BudgetHealth
    TYPES = %w[Expense Income].freeze

    COMMITTED_STATUSES = [ Status::APPROVED, Status::SUBMITTED, Status::PAID ].freeze

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true
    has_many :expenses, class_name: "Reimbursements::Expense",
                        dependent: :nullify, inverse_of: :budget
    # Income budgets carry their reconciled EUSA credits directly on budget_id;
    # Expense budgets' actuals hang off their expenses (expense.eusa_actuals).
    has_many :eusa_actuals, class_name: "Reimbursements::EusaActual",
                            dependent: :nullify, inverse_of: :budget
    has_many :forecasts, class_name: "Reimbursements::BudgetForecast",
                         dependent: :destroy, inverse_of: :budget
    has_many :budget_ownerships, class_name: "Reimbursements::BudgetOwner",
                                 dependent: :destroy, inverse_of: :budget
    has_many :owners, through: :budget_ownerships, source: :person

    validates :name, presence: true
    validates :budget_type, inclusion: { in: TYPES }

    # The PORO exposed owner links as an array of People record ids; OwnerReview
    # and the budgets UI compare them against person.record_id strings.
    def owner_ids
      owners.map(&:record_id)
    end

    # Diff-syncs the owners join table to exactly +person_ids+ (numeric ids)
    # — the one sync path for the store's budget edit and the importer.
    def sync_owner_ids!(person_ids)
      person_ids = person_ids.map(&:to_i)
      budget_ownerships.where.not(person_id: person_ids).destroy_all
      (person_ids - budget_ownerships.pluck(:person_id)).each do |person_id|
        budget_ownerships.create!(person_id: person_id)
      end
    end

    # The rollups use the association preload when the store loaded it (the
    # budgets index would otherwise pay ~3 queries per card), falling back to
    # SQL for a budget loaded on its own.
    def committed_amount
      @committed_amount ||=
        if expenses.loaded?
          expenses.select { |e| COMMITTED_STATUSES.include?(e.status) }.sum { |e| e.amount_excl_vat || 0 }
        else
          expenses.where(status: COMMITTED_STATUSES).sum(:amount_excl_vat)
        end
    end

    def total_paid
      @total_paid ||=
        if expenses.loaded?
          expenses.select { |e| e.status == Status::PAID }.sum { |e| e.amount_excl_vat || 0 }
        else
          expenses.where(status: Status::PAID).sum(:amount_excl_vat)
        end
    end

    def current_forecast
      return @current_forecast if defined?(@current_forecast)

      @current_forecast =
        if forecasts.loaded?
          forecasts.max_by { |f| [ f.date || Date.new(0), f.id ] }&.amount
        else
          forecasts.order(date: :desc, id: :desc).first&.amount
        end
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

    # --- Overview rollups (Track G) ----------------------------------------
    # The "current plan" for the line: the latest logged forecast, falling back
    # to the initial figure when none has been logged. Nil only when neither
    # exists (an untracked line).
    def projected_amount
      current_forecast || initial_budget
    end

    # The portal's own view of what's been paid (status = Paid). Named to sit
    # beside eusa_actual_amount, whose divergence from it is a reconciliation
    # signal.
    def paid_portal_amount
      total_paid
    end

    # The EUSA ledger's view of what actually landed on this line, NET. For an
    # Expense budget that's the debits less the credits on the actuals
    # reconciled to its expenses; for an Income budget it's the credits less the
    # debits booked directly against the budget. Netting matters both ways: a
    # supplier refund or a credit note genuinely reduces what a line cost, and
    # summing debits alone left a £900 line reading £900 when the true net was
    # £600 (and dragged expected_outturn up with it).
    def eusa_actual_amount
      @eusa_actual_amount ||= income? ? credit_actual_total : debit_actual_total
    end

    # Pending expenses not yet approved: money in the pipeline that hasn't
    # reached Committed. Kept separate so Committed keeps its meaning
    # (Approved/Submitted/Paid).
    def pipeline_amount
      @pipeline_amount ||=
        if expenses.loaded?
          expenses.select { |e| e.status == Status::PENDING }.sum { |e| e.amount_excl_vat || 0 }
        else
          expenses.where(status: Status::PENDING).sum(:amount_excl_vat)
        end
    end

    # The most this line could realistically end up COSTING: the greater of the
    # current projection and what's already been spent or committed, so the
    # number never drops below reality as spend lands.
    #
    # Nil for an Income budget, deliberately. The same max over income figures
    # is best-case income, the opposite direction from "never drops below
    # reality" — a £8,000 target with £3,000 banked would report £8,000 as
    # though it were assured. Better blank than confidently wrong; the
    # projection and the EUSA actual are both still shown on their own.
    def expected_outturn
      return nil if income?

      [ projected_amount, committed_amount, paid_portal_amount, eusa_actual_amount ].compact.max
    end

    private

    # Income booked straight against an Income budget (budget_id set), credits
    # less debits: a debit on an income line is income handed back.
    # (#to_a on a loaded association reuses the preload, so this stays one query
    # for a budget loaded on its own and none for one the store preloaded.)
    def credit_actual_total
      -EusaActual.net(eusa_actuals.to_a)
    end

    # Spend on the actuals reconciled to this budget's expenses, debits less
    # credits. Both branches net through EusaActual.net (which also drops
    # offsetting legs), so a preloaded and a freshly-queried budget can never
    # report different figures.
    def debit_actual_total
      if expenses.loaded? && expenses.all? { |e| e.association(:eusa_actuals).loaded? }
        expenses.sum { |e| EusaActual.net(e.eusa_actuals) }
      else
        EusaActual.net(EusaActual.where(expense_id: expenses.map(&:id)).to_a)
      end
    end
  end
end
