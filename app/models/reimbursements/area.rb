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
  # A show, project or heading that several budget lines belong to.
  #
  # The area holds the AGREED TOTAL and the owners; its budgets hold the
  # nominal code (EUSA's axis) and an optional allocation. See
  # docs/superpowers/specs/2026-09-10-area-grouping-design.md.
  class Area < ApplicationRecord
    include RecordId

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true
    has_many :budgets, class_name: "Reimbursements::Budget", dependent: :nullify,
                       inverse_of: :area
    has_many :area_ownerships, class_name: "Reimbursements::AreaOwner", dependent: :destroy,
                               inverse_of: :area
    has_many :owners, through: :area_ownerships, source: :person
    has_many :forecasts, class_name: "Reimbursements::BudgetForecast", dependent: :destroy,
                         inverse_of: :area

    # What the agreed total is a total OF. A show's total is a SPEND CAP: the
    # £800 it raises buys it no more room. A committee's is a NET allowance:
    # money it raises genuinely raises what it may spend. The area declares
    # which, because it is genuinely both (Mick, 2026-09-11) and neither
    # reading can be derived from the lines.
    BASIS_EXPENSES = "expenses".freeze
    BASIS_NET = "net".freeze

    # The basis is a QUALIFIER on "Agreed total", the noun the form field, the
    # areas index and the overview card already use — not a second name for one
    # stored number. "Total expenses" alone reads as money already spent, and on
    # the overview card it sits directly above "Subtotal Cogito (Expense)".
    #
    # ONE source for the words, written here: every card's label, the two radios
    # (through BASIS_OPTIONS) and the areas index's per-cell qualifier, so a
    # finance user reads back the words they picked and no two screens name one
    # basis differently.
    BASIS_QUALIFIERS = { BASIS_EXPENSES => "expenses", BASIS_NET => "net" }.freeze
    BASIS_LABELS = BASIS_QUALIFIERS.transform_values { |word| "Agreed total (#{word})" }.freeze
    BASES = BASIS_LABELS.keys.freeze
    # simple_form wants [text, value] pairs; BASIS_LABELS is value => text.
    # Derived here rather than inverted in the view, which put the vocabulary
    # in two places.
    BASIS_OPTIONS = BASIS_LABELS.map { |value, text| [ text, value ] }.freeze

    validates :name, presence: true
    # has_attribute?, not a bare inclusion: BackfillReimbursementsAreas creates
    # areas through this model, and on a re-migrate after a rollback it runs
    # BEFORE the migration adding this column — where reading the attribute
    # raises NoMethodError and stops the whole chain, so the areas can be
    # unwound but never put back.
    validates :budget_basis, inclusion: { in: BASES }, if: -> { has_attribute?(:budget_basis) }
    # Areas are matched by name within one (financial year, cost centre) —
    # the backfill and the (future) importer both bind a budget to its parent
    # this way. The composite index on the same three columns is deliberately
    # NOT unique: MySQL allows several NULLs through a unique index, and an
    # area created before a year or centre is assigned has NULLs in exactly
    # those two columns, so only this model validation catches a same-name
    # collision there.
    validates :name, uniqueness: { scope: [ :financial_year_id, :cost_centre_id ] }

    accepts_nested_attributes_for :budgets, allow_destroy: false, reject_if: :all_blank

    # Owner links are People record id STRINGS, mirroring Budget#owner_ids —
    # OwnerReview and the budgets UI compare them against person.record_id.
    def owner_ids
      owners.map(&:record_id)
    end

    # Diff-syncs the owners join table to exactly +person_ids+ (numeric ids) —
    # the sync path for the area edit form and the importer.
    def sync_owner_ids!(person_ids)
      person_ids = person_ids.map(&:to_i)
      area_ownerships.where.not(person_id: person_ids).destroy_all
      (person_ids - area_ownerships.pluck(:person_id)).each do |person_id|
        area_ownerships.create!(person_id: person_id)
      end
    end

    # Latest wins, by date then id — the same rule Budget#current_forecast uses
    # (app/models/reimbursements/budget.rb). Plain `||=` is fine on a nil result
    # here: calling #max_by on the forecasts association loads and caches it
    # regardless, so a re-run only repeats the in-memory sort. Budget's sibling
    # needs `return @x if defined?(@x)` because its unpreloaded branch issues a
    # fresh query each time instead of going through the cached association —
    # don't "fix" this one to match without checking that first.
    def current_forecast
      @current_forecast ||= forecasts.max_by { |f| [ f.date || Date.new(0), f.id ] }&.amount
    end

    def projected_amount = current_forecast || initial_budget

    # The spend its budgets have committed — Approved, Submitted and Paid, ex-VAT,
    # exactly as Budget#committed_amount counts it.
    def committed_amount
      @committed_amount ||= budgets.sum(&:committed_amount)
    end

    # What is left of the AGREED total. Nil when nobody agreed one, rather than
    # reading as the whole spend being over budget.
    #
    # The one figure on a basis-labelled card that does NOT read the basis, by
    # decision. #committed_amount counts CLAIMS, and a claim filed against an
    # income line is spend recorded on it rather than income received, so
    # netting it would raise the room left by money somebody spent. Income that
    # landed is Budget#eusa_actual_amount, an EUSA ledger figure weeks later,
    # and nothing in this portal mixes a committed figure with an actual one.
    #
    # The consequence, which is what makes it safe rather than merely
    # defensible: on a NET area whose income HAS landed this reads LOWER than
    # the room really left. Understating is the direction this portal errs in,
    # so it stands until a basis-aware figure earns its own name and its own
    # decision about whether an EUSA credit may raise it.
    def remaining
      return nil if projected_amount.nil?

      projected_amount - committed_amount
    end

    # How much of the total has been split out into category lines. Lines with no
    # agreed figure are skipped, not counted as zero.
    #
    # Read on the area's own basis, which is the ONLY arithmetic the basis
    # governs: an income line is left out of a spend cap entirely and
    # subtracted from a net allowance. It must not reach AreaRollup#by_type,
    # whose two subtotals never net the types together.
    def allocated
      @allocated ||= net_basis? ? allocated_spend - allocated_income : allocated_spend
    end

    # The two halves every screen prints instead of a bare negative — see
    # ReimbursementsHelper#reimbursements_area_allocation, which owns that rule.
    def allocated_spend = @allocated_spend ||= projections_of { |budget| !budget.income? }
    def allocated_income = @allocated_income ||= projections_of(&:income?)

    # The part of the agreed total not yet assigned to a category — NOT spare money.
    def unallocated
      return nil if projected_amount.nil?

      projected_amount - allocated
    end

    def income? = budgets.any?(&:income?)

    def net_basis? = budget_basis == BASIS_NET

    def basis_label = BASIS_LABELS[budget_basis]

    def basis_qualifier = BASIS_QUALIFIERS[budget_basis]

    private

    # A line nobody has given a figure is skipped, not counted as zero.
    def projections_of(&matcher)
      budgets.select(&matcher).filter_map(&:projected_amount).sum
    end
  end
end
