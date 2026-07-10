# == Schema Information
#
# Table name: reimbursements_cost_centres
# Database name: primary
#
#  id                            :bigint           not null, primary key
#  eusa_code                     :string(255)      not null
#  eusa_recipient                :string(255)
#  eusa_signature_name           :string(255)
#  key                           :string(255)      not null
#  last_nightly_run_on           :date
#  name                          :string(255)      not null
#  nightly_run_days              :string(255)      default([2, 4]), not null
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

    # nightly_run_days holds Ruby wday numbers (0=Sun..6=Sat); the seed/default
    # is [2, 4] = Tue/Thu. Stored as a JSON string so it round-trips through a
    # plain string column (MySQL can't default a TEXT/JSON column).
    NIGHTLY_DEFAULT_DAYS = [ 2, 4 ].freeze
    serialize :nightly_run_days, coder: JSON

    validates :key, presence: true, uniqueness: true
    validates :name, :eusa_code, :receive_mailbox, :send_mailbox, presence: true
    validate :nightly_run_days_are_weekday_numbers

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

    # --- Nightly auto-submit scheduling -----------------------------------
    # Ports bedlam-bacs nightly_support.py (most_recent_run_day / is_due),
    # storing the last-completed date on the row instead of nightly_state.toml.
    # +nightly_run_days+ uses Ruby wday (0=Sun..6=Sat), so [2, 4] = Tue/Thu.

    # Is +date+ one of the configured run-days? The plain schedule check.
    def nightly_run_today?(date = Date.current)
      Array(nightly_run_days).include?(date.wday)
    end

    # The most recent configured run-day on or before +date+ (looking back up to
    # a week), or nil if no run-days are configured.
    def most_recent_nightly_run_day(date = Date.current)
      return nil if Array(nightly_run_days).empty?

      (0..6).each do |delta|
        day = date - delta
        return day if nightly_run_today?(day)
      end
      nil
    end

    # Whether the nightly should act now: a configured run-day has come due and
    # hasn't been handled yet. Covers a catch-up run for a day the job missed
    # (server down) and de-duplicates via +last_nightly_run_on+ so a given
    # run-day fires at most once.
    def nightly_due?(date = Date.current)
      target = most_recent_nightly_run_day(date)
      return false if target.nil?
      return true if last_nightly_run_on.nil?

      last_nightly_run_on < target
    end

    # The next configured run-day strictly after +date+, for "try again on…"
    # copy in the manual-review email. nil if no run-days are configured.
    def next_nightly_run_day(date = Date.current)
      return nil if Array(nightly_run_days).empty?

      (1..7).each do |delta|
        day = date + delta
        return day if nightly_run_today?(day)
      end
      nil
    end

    # Record a completed run so nightly_due? won't fire again for this run-day.
    def record_nightly_run!(date = Date.current)
      update!(last_nightly_run_on: date)
    end

    private

    def folder(drive_id, folder_id)
      return nil if drive_id.blank? || folder_id.blank?

      Folder.new(drive_id: drive_id, folder_id: folder_id)
    end

    def nightly_run_days_are_weekday_numbers
      days = nightly_run_days
      unless days.is_a?(Array) && days.all? { |d| d.is_a?(Integer) && d.between?(0, 6) }
        errors.add(:nightly_run_days, "must be a list of weekday numbers (0=Sun..6=Sat)")
      end
    end
  end
end
