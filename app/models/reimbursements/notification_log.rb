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
  # One email the portal sent, to one recipient. It records that the portal HANDED the message
  # to Graph: a bounce afterwards is invisible here, so a reminder to a dead address looks like
  # one that arrived.
  class NotificationLog < ApplicationRecord
    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true

    validates :kind, :recipient, :sent_at, presence: true

    scope :recent_first, -> { order(sent_at: :desc, id: :desc) }
    scope :for_recipient, ->(address) { where(recipient: address.to_s.strip) }

    # One row per recipient. Never raises: an unlogged email that went out beats a failed log
    # write stopping the portal telling somebody their claim was rejected.
    def self.record(kind:, recipients:, subject:, cost_centre:, sent_at: Time.current)
      Array(recipients).map(&:to_s).map(&:strip).reject(&:blank?).uniq.each do |recipient|
        create!(kind: kind, recipient: recipient, subject: subject,
                cost_centre: cost_centre, sent_at: sent_at)
      end
    rescue StandardError => e
      Rails.logger.warn("Reimbursements: could not log a notification (#{kind}) — #{e.message}")
      nil
    end

    def self.recent(limit:, cost_centre: nil)
      scope = recent_first.includes(:cost_centre).limit(limit)
      cost_centre ? scope.where(cost_centre_id: [ cost_centre.id, nil ]) : scope
    end
  end
end
