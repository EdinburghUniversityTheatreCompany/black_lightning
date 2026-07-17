# == Schema Information
#
# Table name: reimbursements_batch_attempts
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  bacs_date          :date
#  error_messages     :text(65535)
#  status             :string(255)      default("building"), not null
#  triggered_by_email :string(255)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  batch_record_id    :string(255)
#  cost_centre_id     :bigint           not null
#
# Indexes
#
#  idx_on_cost_centre_id_status_4ce6fe61ad                (cost_centre_id,status)
#  index_reimbursements_batch_attempts_on_cost_centre_id  (cost_centre_id)
#
# Foreign Keys
#
#  fk_rails_...  (cost_centre_id => reimbursements_cost_centres.id)
#
module Reimbursements
  ##
  # One Build Batch run, from click to outcome. BuildBatchJob is a background
  # job whose only failure signal used to be an email: History had no in-app
  # trace of a build that was still running, failed before the Airtable Batch
  # record existed, or found nothing to build. The controller creates a row the
  # moment the operator clicks (status "building"); the job resolves it to
  # completed / failed / nothing_to_build. Airtable's schema isn't ours to
  # change, so this log lives in MySQL (and survives the planned cutover).
  class BatchAttempt < ApplicationRecord
    STATUSES = %w[building completed failed nothing_to_build].freeze

    # A build normally finishes well inside BuildBatchJob's 30-minute
    # concurrency window; a "building" row older than this means the job died
    # with its retries exhausted (or the queue is stuck) and History should say
    # so instead of showing an eternal spinner.
    STALE_AFTER = 30.minutes

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre"

    validates :status, inclusion: { in: STATUSES }

    scope :building, -> { where(status: "building") }
    # Everything History needs to surface: in-flight builds, failures, no-op
    # runs, and completed-with-warnings — a cleanly completed attempt is
    # redundant with the Batch row itself.
    scope :needing_attention, lambda {
      where(status: %w[building failed nothing_to_build])
        .or(where(status: "completed").where.not(error_messages: [ nil, "" ]))
    }
    scope :recent_first, -> { order(created_at: :desc) }

    def building? = status == "building"
    def completed? = status == "completed"
    def failed? = status == "failed"
    def nothing_to_build? = status == "nothing_to_build"

    def stale?
      building? && created_at < STALE_AFTER.ago
    end

    def resolve!(status:, error_messages: nil, batch_record_id: nil)
      update!(status: status, error_messages: error_messages.presence,
              batch_record_id: batch_record_id.presence)
    end
  end
end
