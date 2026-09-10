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
    # (app/models/reimbursements/budget.rb).
    def current_forecast
      @current_forecast ||= forecasts.max_by { |f| [ f.date || Date.new(0), f.id ] }&.amount
    end

    def projected_amount = current_forecast || initial_budget
  end
end
