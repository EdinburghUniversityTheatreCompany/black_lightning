# == Schema Information
#
# Table name: reimbursements_areas
# Database name: primary
#
#  id                :bigint           not null, primary key
#  active            :boolean          default(TRUE), not null
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

    validates :name, presence: true
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
    def remaining
      return nil if projected_amount.nil?

      projected_amount - committed_amount
    end

    # How much of the total has been split out into category lines. Lines with no
    # agreed figure are skipped, not counted as zero.
    def allocated
      @allocated ||= budgets.filter_map(&:projected_amount).sum
    end

    # The part of the agreed total not yet assigned to a category — NOT spare money.
    def unallocated
      return nil if projected_amount.nil?

      projected_amount - allocated
    end

    def income? = budgets.any?(&:income?)
  end
end
