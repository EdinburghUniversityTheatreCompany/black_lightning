# == Schema Information
#
# Table name: reimbursements_notification_logs
# Database name: primary
#
#  id             :bigint           not null, primary key
#  kind           :string(255)      not null
#  recipient      :string(255)      not null
#  sent_at        :datetime         not null
#  subject        :string(255)
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  cost_centre_id :bigint
#
# Indexes
#
#  index_reimbursements_notification_logs_on_centre     (cost_centre_id,sent_at)
#  index_reimbursements_notification_logs_on_recipient  (recipient,sent_at)
#  index_reimbursements_notification_logs_on_sent_at    (sent_at,id)
#
# Foreign Keys
#
#  fk_rails_...  (cost_centre_id => reimbursements_cost_centres.id)
#
module Reimbursements
  ##
  # A record of one email the portal sent, to one recipient.
  #
  # Integration Status could say whether Graph was reachable and when each cost
  # centre's nightly last completed, and nothing about what was sent to whom —
  # so "did this person get their reminder?" had no answer short of asking
  # them. A reminder that went to a dead address looked exactly like one that
  # arrived.
  #
  # What it records is that the portal HANDED the message to Graph, which is
  # all it can honestly claim: a bounce afterwards is invisible here, the same
  # limit the batch's "Producer emails: sent" badge states.
  class NotificationLog < ApplicationRecord
    include RecordId

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true

    validates :kind, :recipient, :sent_at, presence: true

    scope :recent_first, -> { order(sent_at: :desc, id: :desc) }
    scope :for_recipient, ->(address) { where(recipient: address.to_s.strip) }

    # One row per recipient of one message. Never raises: an email that went
    # out but was not logged is a far better outcome than a log write that
    # stops the portal telling somebody their claim was rejected, so the
    # caller's send is never put at risk by this.
    def self.record(kind:, recipients:, subject:, cost_centre:, sent_at: Time.current)
      Array(recipients).map(&:to_s).map(&:strip).reject(&:blank?).uniq.each do |recipient|
        create!(kind: kind, recipient: recipient, subject: subject,
                cost_centre: cost_centre, sent_at: sent_at)
      end
    rescue StandardError => e
      Rails.logger.warn("Reimbursements: could not log a notification (#{kind}) — #{e.message}")
      nil
    end

    # The last +limit+ sends, newest first. The Status page's own read.
    def self.recent(limit:, cost_centre: nil)
      scope = recent_first.includes(:cost_centre).limit(limit)
      cost_centre ? scope.where(cost_centre_id: [ cost_centre.id, nil ]) : scope
    end
  end
end
