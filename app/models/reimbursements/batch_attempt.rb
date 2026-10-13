# == Schema Information
#
# Table name: reimbursements_batch_attempts
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  bacs_date          :date
#  dismissed_at       :datetime
#  dismissed_by_email :string(255)
#  draft_web_link     :text(65535)
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
  # One Build Batch run, from click to outcome: History's only trace of a build
  # that is still running, failed before its Batch existed, or found nothing.
  # Created "building" at the click; BuildBatchJob resolves it.
  class BatchAttempt < ApplicationRecord
    STATUSES = %w[building completed failed nothing_to_build].freeze

    # Blank, not nil: nil means unrecorded (see #resolve!).
    NO_DRAFT = "".freeze

    # BuildBatchJob's concurrency window: a "building" row older than this
    # means the job died or the queue is stuck, not a long build.
    STALE_AFTER = 30.minutes

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre"

    validates :status, inclusion: { in: STATUSES }

    # A clean build is redundant with its Batch, and nothing_to_build is the
    # expected outcome of a serialised double-click, so neither is alerted on.
    # The trailing where applies to the whole OR.
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

    # Hides the alert; the record stays.
    def dismiss!(email: nil)
      update!(dismissed_at: Time.current, dismissed_by_email: email.presence)
    end

    # A running build resolves itself within minutes; offering to hide it
    # invites hiding something live.
    def dismissible? = !building? || stale?

    # Whether building again is safe turns on whether this build made its EUSA
    # draft, so +draft_web_link+ records it: the draft's link, NO_DRAFT when it
    # made none, nil when nothing recorded either (no result in hand, or an
    # attempt resolved before the column existed).
    def resolve!(status:, error_messages: nil, batch_record_id: nil, draft_web_link: nil)
      update!(status: status, error_messages: error_messages.presence,
              batch_record_id: batch_record_id.presence, draft_web_link: draft_web_link)
    end

    def made_draft? = draft_web_link.present?
    def draft_unknown? = draft_web_link.nil?

    # Reopening a batch makes building it again safe, so its build's alerts
    # (a failed one says not to build again) no longer apply.
    def self.dismiss_for_batch!(batch_record_id, email: nil)
      where(batch_record_id: batch_record_id.to_s, dismissed_at: nil)
        .find_each { |attempt| attempt.dismiss!(email: email) }
    end
  end
end
