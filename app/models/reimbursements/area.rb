# == Schema Information
#
# Table name: reimbursements_areas
# Database name: primary
#
#  id                :bigint           not null, primary key
#  active            :boolean          default(TRUE), not null
#  budget_basis      :string(255)      default("expenses"), not null
#  initial_budget    :decimal(12, 2)
#  name              :string(255)      not null
#  notes             :text(65535)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  cost_centre_id    :bigint
#  financial_year_id :bigint
#
# Indexes
#
#  index_reimbursements_areas_on_cost_centre_id     (cost_centre_id)
#  index_reimbursements_areas_on_financial_year_id  (financial_year_id)
#  index_reimbursements_areas_on_year_centre_name   (financial_year_id,cost_centre_id,name)
#
# Foreign Keys
#
#  fk_rails_...  (cost_centre_id => reimbursements_cost_centres.id)
#  fk_rails_...  (financial_year_id => reimbursements_financial_years.id)
#
module Reimbursements
  ##
  # A show, project or heading that several budget lines belong to. It holds the
  # AGREED TOTAL and the owners; its budgets hold the nominal code and an
  # optional allocation. See docs/superpowers/specs/2026-09-10-area-grouping-design.md.
  class Area < ApplicationRecord
    include RecordId
    include PlannedAmount

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true
    has_many :budgets, class_name: "Reimbursements::Budget", dependent: :nullify,
                       inverse_of: :area
    has_many :area_ownerships, class_name: "Reimbursements::AreaOwner", dependent: :destroy,
                               inverse_of: :area
    has_many :owners, through: :area_ownerships, source: :person
    has_many :forecasts, class_name: "Reimbursements::BudgetForecast", dependent: :destroy,
                         inverse_of: :area

    # What the agreed total is a total OF. A show's is a SPEND CAP (income it
    # raises buys no more room); a committee's is a NET allowance (income raises
    # what it may spend). The lines cannot say which, so the area declares it.
    BASIS_EXPENSES = "expenses".freeze
    BASIS_NET = "net".freeze

    # The basis qualifies "Agreed total" ("Total expenses" alone reads as money
    # already spent). Every card label, both radios and the areas index's
    # qualifier come from here, so a finance user reads back the words they
    # picked and no two screens name a basis differently.
    BASIS_QUALIFIERS = { BASIS_EXPENSES => "expenses", BASIS_NET => "net" }.freeze
    BASIS_LABELS = BASIS_QUALIFIERS.transform_values { |word| "Agreed total (#{word})" }.freeze
    BASES = BASIS_LABELS.keys.freeze
    # simple_form wants [text, value] pairs.
    BASIS_OPTIONS = BASIS_LABELS.map { |value, text| [ text, value ] }.freeze

    validates :name, presence: true
    # has_attribute?, because on a re-migrate after a rollback the backfill
    # creates areas through this model BEFORE the migration adding the column,
    # and a bare inclusion would raise NoMethodError and stop the chain.
    validates :budget_basis, inclusion: { in: BASES }, if: -> { has_attribute?(:budget_basis) }
    # Areas are matched by name within one (year, centre), as the backfill and
    # the importer do. The composite index is deliberately NOT unique: MySQL lets
    # several NULLs through, and an area with no year or centre yet has NULLs in both.
    validates :name, uniqueness: { scope: [ :financial_year_id, :cost_centre_id ] }

    # NOT :all_blank: the Type select has no blank option, so an untouched "Add
    # budget line" row still posts budget_type and would reach save! with no name.
    # Untouched means the fields the operator fills in are blank.
    # AreasController#budget_row_error calls this same lambda, and the two must
    # agree: a row one calls untouched and the other incomplete is a silent 500 or
    # a silently dropped line. A figure typed with no name counts as touched, so it
    # is reported.
    UNTOUCHED_BUDGET_ROW = lambda do |attrs|
      attrs["id"].blank? && %w[name nominal_code initial_budget].all? { |key| attrs[key].blank? }
    end

    accepts_nested_attributes_for :budgets, reject_if: UNTOUCHED_BUDGET_ROW

    # People record id STRINGS, as Budget#owner_ids: OwnerReview compares them
    # against person.record_id.
    def owner_ids
      owners.map(&:record_id)
    end

    # Diff-syncs the join table to exactly +person_ids+ (numeric ids).
    def sync_owner_ids!(person_ids)
      person_ids = person_ids.map(&:to_i)
      area_ownerships.where.not(person_id: person_ids).destroy_all
      (person_ids - area_ownerships.pluck(:person_id)).each do |person_id|
        area_ownerships.create!(person_id: person_id)
      end
    end

    # Latest by date then id, as Budget#current_forecast. Plain ||= is fine on a
    # nil result here, unlike Budget's defined? sibling: #max_by loads and caches
    # the association whatever it returns. Don't "fix" it to match.
    def current_forecast
      @current_forecast ||= forecasts.max_by { |f| [ f.date || Date.new(0), f.id ] }&.amount
    end

    def projected_amount = current_forecast || initial_budget

    # Approved, Submitted and Paid spend, ex-VAT, as Budget#committed_amount counts it.
    def committed_amount
      @committed_amount ||= budgets.sum(&:committed_amount)
    end

    # What is left of the agreed total; nil when nobody agreed one, not "overspent".
    #
    # Deliberately does not read the basis: committed_amount counts CLAIMS, and a
    # claim on an income line is spend recorded there, not income received, so
    # netting it would raise the room left by money somebody spent. On a net area
    # whose income has landed this therefore reads lower than the room really
    # left, which is the direction this portal errs in.
    def remaining
      return nil if no_budget_set?

      projected_amount - committed_amount
    end

    # A £0 total counts as unset only while nothing is allocated under it
    # (production has many termtime areas like that, with real spend). Lines
    # under a £0 total contradict it, and that is worth showing.
    def nothing_allocated?
      allocated.zero?
    end

    # How much of the total is split out into lines; lines with no figure are
    # skipped, not counted as zero. On the area's own basis, the only arithmetic
    # the basis governs: it must not reach AreaRollup#by_type, whose subtotals
    # never net the types.
    def allocated
      @allocated ||= net_basis? ? allocated_spend - allocated_income : allocated_spend
    end

    # The two halves screens print instead of a bare negative (see
    # ReimbursementsHelper#reimbursements_area_allocation).
    def allocated_spend = @allocated_spend ||= projections_of { |budget| !budget.income? }
    def allocated_income = @allocated_income ||= projections_of(&:income?)

    # The part of the agreed total not yet assigned to a line, NOT spare money.
    def unallocated
      return nil if no_budget_set?

      projected_amount - allocated
    end

    def net_basis? = budget_basis == BASIS_NET

    def basis_label = BASIS_LABELS[budget_basis]

    def basis_qualifier = BASIS_QUALIFIERS[budget_basis]

    private

    def projections_of(&matcher)
      budgets.select(&matcher).filter_map(&:projected_amount).sum
    end
  end
end
