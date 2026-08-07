# == Schema Information
#
# Table name: reimbursements_batch_attempts
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  bacs_date          :date
#  dismissed_at       :datetime
#  dismissed_by_email :string(255)
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
#  idx_batch_attempts_on_cost_centre_and_dismissed        (cost_centre_id,dismissed_at)
#  idx_on_cost_centre_id_status_4ce6fe61ad                (cost_centre_id,status)
#  index_reimbursements_batch_attempts_on_cost_centre_id  (cost_centre_id)
#
# Foreign Keys
#
#  fk_rails_...  (cost_centre_id => reimbursements_cost_centres.id)
#
module Reimbursements
  ##
  # One Build Batch run, from click to outcome. BuildBatchJob runs in the
  # background, so without this row a build that is still running, failed
  # before the Batch record existed, or found nothing to build leaves no trace
  # on History at all — its only failure signal is an email. The controller
  # creates the row the moment the operator clicks (status "building"); the job
  # resolves it to completed / failed / nothing_to_build.
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
    # What History surfaces as a persistent alert: in-flight builds, failures,
    # and completed-with-warnings. A cleanly completed attempt is redundant with
    # the Batch row itself, and "nothing_to_build" is the benign, expected
    # outcome of a serialised double-click — surfacing it for days would be
    # pure noise, so it's recorded but not alerted on.
    # The trailing where applies to the whole OR, giving
    # "(building OR failed OR completed-with-warnings) AND not dismissed".
    scope :needing_attention, lambda {
      where(status: %w[building failed])
        .or(where(status: "completed").where.not(error_messages: [ nil, "" ]))
        .where(dismissed_at: nil)
    }
    scope :recent_first, -> { order(created_at: :desc) }

    def building? = status == "building"
    def completed? = status == "completed"
    def failed? = status == "failed"
    def nothing_to_build? = status == "nothing_to_build"

    def stale?
      building? && created_at < STALE_AFTER.ago
    end

    def dismissed? = dismissed_at.present?

    # An operator saying "I have dealt with this", not a correction of the
    # record: the row keeps its status, its errors and its batch_record_id, so
    # a dismissed attempt still reads as a failure in the audit trail.
    def dismiss!(email: nil)
      update!(dismissed_at: Time.current, dismissed_by_email: email.presence)
    end

    # A build still running resolves itself within minutes, so offering to hide
    # it would only invite hiding something live. Everything else is waiting on
    # a human and should be clearable once they have acted.
    def dismissable? = !(building? && !stale?)

    def resolve!(status:, error_messages: nil, batch_record_id: nil)
      update!(status: status, error_messages: error_messages.presence,
              batch_record_id: batch_record_id.presence)
    end
  end
end
