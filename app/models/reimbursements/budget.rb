# == Schema Information
#
# Table name: reimbursements_budgets
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  active                  :boolean          default(TRUE), not null
#  area_before_rollback    :json
#  budget_type             :string(255)      default("Expense"), not null
#  initial_budget          :decimal(12, 2)
#  name                    :string(255)      default(""), not null
#  name_before_area_rename :string(255)
#  nominal_code            :string(255)      default(""), not null
#  notes                   :text(65535)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  airtable_record_id      :string(255)
#  area_id                 :bigint
#  cost_centre_id          :bigint
#  financial_year_id       :bigint
#
# Indexes
#
#  index_reimbursements_budgets_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_reimbursements_budgets_on_area_id             (area_id)
#  index_reimbursements_budgets_on_cost_centre_id      (cost_centre_id)
#  index_reimbursements_budgets_on_financial_year_id   (financial_year_id)
#  index_reimbursements_budgets_on_nominal_code        (nominal_code)
#
# Foreign Keys
#
#  fk_rails_...  (area_id => reimbursements_areas.id)
#  fk_rails_...  (cost_centre_id => reimbursements_cost_centres.id)
#  fk_rails_...  (financial_year_id => reimbursements_financial_years.id)
#
module Reimbursements
  ##
  # A budget line. Its rollups are computed, never stored, all excl-VAT like the
  # BACS spreadsheet:
  #
  #   committed_amount   = Σ amount_excl_vat, status ∈ {Approved, Submitted, Paid}
  #   paid_portal_amount = Σ amount_excl_vat, status = Paid
  #   current_forecast   = latest forecast's amount (nil when none logged)
  #   projected_amount   = current_forecast, else initial_budget (the PLAN)
  #   remaining          = projected_amount − committed_amount (nil with no plan)
  #   variance           = projected_amount − initial_budget (nil without initial)
  #
  # Each is memoized per instance; one store lives per request.
  class Budget < ApplicationRecord
    include RecordId
    include BudgetHealth
    include PlannedAmount
    TYPES = %w[Expense Income].freeze

    COMMITTED_STATUSES = [ Status::APPROVED, Status::SUBMITTED, Status::PAID ].freeze

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true
    belongs_to :area, class_name: "Reimbursements::Area", optional: true, inverse_of: :budgets
    has_many :expenses, class_name: "Reimbursements::Expense",
                        dependent: :nullify, inverse_of: :budget
    # Income budgets carry their reconciled EUSA credits directly on budget_id;
    # Expense budgets' actuals hang off their expenses (expense.eusa_actuals).
    has_many :eusa_actuals, class_name: "Reimbursements::EusaActual",
                            dependent: :nullify, inverse_of: :budget
    # Shares of credit rows split across income budgets. A split row carries
    # no budget_id, so these never overlap #eusa_actuals.
    has_many :actual_allocations, class_name: "Reimbursements::ActualAllocation",
                                  dependent: :destroy, inverse_of: :budget
    has_many :forecasts, class_name: "Reimbursements::BudgetForecast",
                         dependent: :destroy, inverse_of: :budget
    has_many :budget_ownerships, class_name: "Reimbursements::BudgetOwner",
                                 dependent: :destroy, inverse_of: :budget
    # Read only for a line in no area. The backfill keeps them on area lines so
    # it can be reversed; there the area's owners are live (#owners).
    has_many :own_owners, through: :budget_ownerships, source: :person

    validates :name, presence: true
    validates :budget_type, inclusion: { in: TYPES }

    # A line made on its area's form has no cost centre or year, and an
    # unstamped line is lenient-scoped into every year's and centre's lists and
    # pickers, so it inherits the area's. Fills BLANKS only, so it never moves a
    # placed line out of its pot (an unstamped line is stamped on its next Save).
    before_validation :inherit_area_scoping

    # The one name for a line read on its own; lists of budgets are ordered by
    # it. The bare name is right only where the area is already beside it.
    # The COLON is correctness: BudgetImport.bare_name splits on it, so a label
    # copied into the committee's sheet resolves to its line, where a dash
    # would bucket as a create (a duplicate line).
    def display_name
      area ? "#{area.name}: #{name}" : name.to_s
    end

    # A <select> label only. It must stay separate from #display_name, which
    # the BACS payment reference, receipt filenames and import matching read.
    # The centre prefix is needed because active_budgets is not centre-scoped.
    def picker_label
      cost_centre ? "#{cost_centre.picker_prefix} - #{display_name}" : display_name
    end

    # The area owns and its budgets inherit. owner_ids are record id STRINGS,
    # compared against person.record_id by OwnerReview and the budgets UI.
    def owners
      area ? area.owners : own_owners
    end

    def owner_ids
      owners.map(&:record_id)
    end

    # Diff-syncs the OWN owner rows to exactly +person_ids+ (numeric ids),
    # whether or not the line is in an area.
    def sync_owner_ids!(person_ids)
      person_ids = person_ids.map(&:to_i)
      budget_ownerships.where.not(person_id: person_ids).destroy_all
      (person_ids - budget_ownerships.pluck(:person_id)).each do |person_id|
        budget_ownerships.create!(person_id: person_id)
      end
    end

    def committed_amount
      @committed_amount ||= expense_total(COMMITTED_STATUSES)
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

    # What is left of the plan (#projected_amount). Nil when nobody set a
    # figure, since a 0 would read as fully overspent. An income line reads its
    # forecast alone: its plan is a target to raise, so falling back to the
    # initial figure would mean nothing.
    def remaining
      plan = income? ? current_forecast : projected_amount
      # A £0 plan is unset, not a cap (PlannedAmount).
      return nil if plan.nil? || no_budget_set?

      plan - committed_amount
    end

    # The plan's drift from the agreed figure: £0.00 with no forecast (the
    # plan IS the agreed figure), nil without an initial budget.
    def variance
      return nil if no_budget_set? || initial_budget.nil?

      projected_amount - initial_budget
    end

    # The plan: the latest forecast, else the initial budget.
    def projected_amount
      current_forecast || initial_budget
    end

    # Paid in the portal. Beside eusa_actual_amount, a gap between the two is a
    # reconciliation signal.
    def paid_portal_amount
      @paid_portal_amount ||= expense_total([ Status::PAID ])
    end

    # What the EUSA ledger says landed on this line, NET: an expense line's
    # debits less credits on its expenses' actuals, an income line's credits
    # less debits booked against it. A refund reduces a line.
    def eusa_actual_amount
      @eusa_actual_amount ||= income? ? credit_actual_total : debit_actual_total
    end

    # Pending claims, kept apart from committed_amount.
    def pipeline_amount
      @pipeline_amount ||= expense_total([ Status::PENDING ])
    end

    # The most the line could end up costing, never below what is already
    # spent or committed. Nil for income, where the same max would read as
    # best-case income.
    def expected_outturn
      return nil if income?

      [ projected_amount, committed_amount, paid_portal_amount, eusa_actual_amount ].compact.max
    end

    private

    # Excl-VAT sum over +statuses+. Reads the store's preload when it is loaded
    # (the index would otherwise pay ~3 queries per line) and SQL otherwise.
    def expense_total(statuses)
      if expenses.loaded?
        expenses.select { |e| statuses.include?(e.status) }.sum { |e| e.amount_excl_vat || 0 }
      else
        expenses.where(status: statuses).sum(:amount_excl_vat)
      end
    end

    def inherit_area_scoping
      return unless area

      self.cost_centre_id ||= area.cost_centre_id
      self.financial_year_id ||= area.financial_year_id
    end

    # Credits less debits booked on the line (a debit is income handed back).
    # #to_a reuses the preload when there is one.
    def credit_actual_total
      -EusaActual.net(eusa_actuals.to_a) + allocated_credit_total
    end

    # This line's shares of split rows, counted beside the rows linked whole:
    # apportion_actual! clears a split row's budget_id, so the sets are
    # disjoint. Reads the preload where budgets_with_actuals loaded it.
    def allocated_credit_total
      if actual_allocations.loaded?
        actual_allocations.sum { |allocation| allocation.amount || 0 }
      else
        actual_allocations.sum(:amount)
      end
    end

    # Debits less credits on the actuals of this line's expenses. Both branches
    # net through EusaActual.net (which drops offsetting legs), so preloaded and
    # fresh reads agree.
    def debit_actual_total
      if expenses.loaded? && expenses.all? { |e| e.association(:eusa_actuals).loaded? }
        expenses.sum { |e| EusaActual.net(e.eusa_actuals) }
      else
        EusaActual.net(EusaActual.where(expense_id: expenses.map(&:id)).to_a)
      end
    end
  end
end
