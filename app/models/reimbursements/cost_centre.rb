# == Schema Information
#
# Table name: reimbursements_cost_centres
# Database name: primary
#
#  id                            :bigint           not null, primary key
#  eusa_code                     :string(255)      not null
#  eusa_recipient                :string(255)
#  key                           :string(255)      not null
#  name                          :string(255)      not null
#  receive_mailbox               :string(255)      not null
#  send_mailbox                  :string(255)      not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  sharepoint_bacs_drive_id      :string(255)
#  sharepoint_bacs_folder_id     :string(255)
#  sharepoint_receipts_drive_id  :string(255)
#  sharepoint_receipts_folder_id :string(255)
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
    # EUSA finance's inbox, the default recipient for the BACS request email.
    DEFAULT_EUSA_RECIPIENT = "finance@eusa.ed.ac.uk".freeze

    # A SharePoint upload destination (a drive + a folder within it).
    Folder = Struct.new(:drive_id, :folder_id, keyword_init: true)

    validates :key, presence: true, uniqueness: true
    validates :name, :eusa_code, :receive_mailbox, :send_mailbox, presence: true

    # The primary cost centre (Fringe today). Multi-cost-centre flows iterate
    # .all; .default is for the single-cost-centre call sites that predate the
    # per-cost-centre work (mailbox poll, mailbox client).
    def self.default
      order(:id).first
    end

    # Where renamed receipts land, or nil until configured (Settings, Phase F).
    def receipts_folder
      folder(sharepoint_receipts_drive_id, sharepoint_receipts_folder_id)
    end

    # Where the BACS xlsx is backed up, or nil until configured.
    def bacs_folder
      folder(sharepoint_bacs_drive_id, sharepoint_bacs_folder_id)
    end

    # Build Batch needs both SharePoint destinations before it can offload files.
    def sharepoint_configured?
      receipts_folder.present? && bacs_folder.present?
    end

    def eusa_recipient_or_default
      eusa_recipient.presence || DEFAULT_EUSA_RECIPIENT
    end

    private

    def folder(drive_id, folder_id)
      return nil if drive_id.blank? || folder_id.blank?

      Folder.new(drive_id: drive_id, folder_id: folder_id)
    end
  end
end
