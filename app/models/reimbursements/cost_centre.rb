# == Schema Information
#
# Table name: reimbursements_cost_centres
# Database name: primary
#
#  id              :bigint           not null, primary key
#  eusa_code       :string(255)      not null
#  key             :string(255)      not null
#  name            :string(255)      not null
#  receive_mailbox :string(255)      not null
#  send_mailbox    :string(255)      not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_reimbursements_cost_centres_on_key  (key) UNIQUE
#
module Reimbursements
  ##
  # A pot of money with its own budgets, admins, EUSA cost-centre code and
  # mailboxes. Fringe (F40) is live; termtime (BED) becomes a second row when the
  # portal takes over termtime payments — a row, not a rewrite.
  #
  # Now an ActiveRecord model (was a frozen in-code value): the business manager
  # edits these operational settings in the UI (Settings, Phase F). Each cost
  # centre has its own +receive_mailbox+ (email-in) and +send_mailbox+ (draft /
  # send-from) — they may differ. Table inferred as reimbursements_cost_centres.
  class CostCentre < ApplicationRecord
    validates :key, presence: true, uniqueness: true
    validates :name, :eusa_code, :receive_mailbox, :send_mailbox, presence: true

    # The primary cost centre (Fringe today). Multi-cost-centre flows iterate
    # .all; .default is for the single-cost-centre call sites that predate the
    # per-cost-centre work (mailbox poll, mailbox client).
    def self.default
      order(:id).first
    end
  end
end
