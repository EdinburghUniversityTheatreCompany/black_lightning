# == Schema Information
#
# Table name: reimbursements_cost_centres
# Database name: primary
#
#  id                            :bigint           not null, primary key
#  eusa_code                     :string(255)      not null
#  eusa_contact_name             :string(255)
#  eusa_recipient                :string(255)
#  eusa_signature_name           :string(255)
#  key                           :string(255)      not null
#  last_nightly_run_on           :date
#  name                          :string(255)      not null
#  nightly_run_days              :string(255)      default([2, 4]), not null
#  notification_email            :string(255)
#  receive_mailbox               :string(255)      not null
#  send_mailbox                  :string(255)      not null
#  sharepoint_site_url           :string(255)
#  short_code                    :string(16)
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
  # A pot of money with its own budgets, EUSA cost-centre code, mailboxes and
  # SharePoint folders, edited by finance on the Settings page.
  class CostCentre < ApplicationRecord
    # EUSA finance's inbox, the default recipient for the BACS request email.
    DEFAULT_EUSA_RECIPIENT = "finance@eusa.ed.ac.uk".freeze

    # A SharePoint upload destination (a drive + a folder within it).
    Folder = Struct.new(:drive_id, :folder_id, keyword_init: true)

    # Cap for +short_code+, which prefixes this centre's budgets in a picker
    # ("BF - Improverts: Other").
    SHORT_CODE_MAX = 16

    # Ruby wdays (0=Sun..6=Sat), stored as a JSON string so it round-trips
    # through a plain string column (MySQL can't default a TEXT/JSON column).
    serialize :nightly_run_days, coder: JSON

    # Both ";" (Outlook's) and "," separate addresses: a list read the other way
    # would go to one unroutable address.
    NOTIFICATION_EMAIL_SEPARATOR = /[;,]/

    # +key+ is the URL slug, derived from the name when left blank.
    before_validation :derive_key_from_name

    validates :key, presence: true, uniqueness: true
    validates :key, format: { with: /\A[a-z0-9-]+\z/,
                              message: "may only contain lowercase letters, numbers and hyphens" },
                    allow_blank: true
    validates :name, :eusa_code, :receive_mailbox, :send_mailbox, presence: true
    # Reminders reaching nobody leave producers waiting with nothing on screen.
    validates :notification_email, presence: true
    validate :notification_email_addresses_are_valid
    validates :eusa_code, uniqueness: true
    validates :short_code, length: { maximum: SHORT_CODE_MAX }, allow_blank: true
    # Two centres sharing a mailbox would make MailboxPollJob file every
    # email-in receipt under whichever centre is polled first.
    validates :receive_mailbox, uniqueness: { case_sensitive: false }
    validates :send_mailbox, uniqueness: { case_sensitive: false }
    validates :receive_mailbox, :send_mailbox, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :eusa_recipient, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
    validate :nightly_run_days_are_weekday_numbers

    # The short code, else the EUSA code every centre has.
    def picker_prefix = short_code.presence || eusa_code

    # order(:id).first, so an ARBITRARY centre once a second row exists. Never
    # use it where the right answer is knowable, nor on a path that moves money
    # or emails a producer; see .sole_configured.
    def self.default
      order(:id).first
    end

    # The only cost centre, or nil once there is a choice to make.
    def self.sole_configured
      all.to_a.then { |centres| centres.one? ? centres.first : nil }
    end

    # Where renamed receipts land, or nil until configured (Settings).
    def receipts_folder
      folder(sharepoint_receipts_drive_id, sharepoint_receipts_folder_id)
    end

    # Where the BACS xlsx is backed up, or nil until configured.
    def bacs_folder
      folder(sharepoint_bacs_drive_id, sharepoint_bacs_folder_id)
    end

    # The upload gate BatchProcessor keys off: the drive and folder ids alone
    # locate a destination (the site URL is only needed to browse for them).
    def sharepoint_configured?
      receipts_folder.present? && bacs_folder.present?
    end

    # Stricter, for the settings badge: also needs the site URL, without which
    # browse/verify is broken and the stored ids may belong to a since-changed site.
    def sharepoint_fully_configured?
      sharepoint_configured? && sharepoint_site_url.present?
    end

    # The site in Graph's path form ("tenant.sharepoint.com:/sites/Finance"), or
    # nil if unset or unparseable. Sites.Selected can't search, so sites are
    # addressed by path.
    def sharepoint_graph_site_path
      return nil if sharepoint_site_url.blank?

      uri = URI.parse(sharepoint_site_url.strip)
      return nil if uri.host.blank?

      "#{uri.host}:#{uri.path.to_s.chomp('/')}"
    rescue URI::InvalidURIError
      nil
    end

    def eusa_recipient_or_default
      eusa_recipient.presence || DEFAULT_EUSA_RECIPIENT
    end

    # The addresses in +notification_email+, blanks and duplicates dropped.
    def notification_emails
      notification_email.to_s.split(NOTIFICATION_EMAIL_SEPARATOR).map(&:strip).compact_blank.uniq
    end

    # Presence-validated, so this only catches a row that predates the
    # validation or was written around it. The nightly then warns and does not
    # record the run-day.
    def notification_recipients_empty?
      notification_emails.empty?
    end

    # --- Wording every email, filename and sign-off takes from the centre ----

    # The bracketed tag on every reimbursements email subject.
    def subject_prefix
      "[#{name}]"
    end

    # Who a person-written finance email is from when no operator name is
    # available (the Build Batch sender field, the EUSA email sign-off).
    def finance_sender_name
      eusa_signature_name.presence || "#{name} Finance"
    end

    # Sign-off for the operator alerts the batch jobs send automatically.
    def automated_sign_off
      "#{name} BACS (automated)"
    end

    # Where a submitter writes with a question: email-in already watches it.
    def contact_email
      receive_mailbox
    end

    # Filename-safe form of the name, for the BACS spreadsheet sent to EUSA.
    def slug
      name.to_s.parameterize
    end

    # --- Nightly reminder schedule (Ruby wdays: [2, 4] is Tue/Thu) ----------

    def nightly_run_today?(date = Date.current)
      Array(nightly_run_days).include?(date.wday)
    end

    # Whether a run-day has come due and not been handled: catches up a day the
    # job missed, and +last_nightly_run_on+ stops one firing twice.
    def nightly_due?(date = Date.current)
      target = (0..6).map { |back| date - back }.find { |day| nightly_run_today?(day) }
      target.present? && (last_nightly_run_on.nil? || last_nightly_run_on < target)
    end

    # The next run-day after +date+, for the approved-ready reminder; nil if none is configured.
    def next_nightly_run_day(date = Date.current)
      (1..7).map { |ahead| date + ahead }.find { |day| nightly_run_today?(day) }
    end

    # update_column, not update!: an unrelated validation (a blank
    # notification_email, the very case REIMBURSEMENTS_OPERATOR_EMAIL covers)
    # must not veto this bookkeeping stamp.
    def record_nightly_run!(date = Date.current)
      update_column(:last_nightly_run_on, date)
    end

    private

    def folder(drive_id, folder_id)
      return nil if drive_id.blank? || folder_id.blank?

      Folder.new(drive_id: drive_id, folder_id: folder_id)
    end

    def derive_key_from_name
      self.key = name.to_s.parameterize if key.blank? && name.present?
    end

    # Every address, so one typo fails the save rather than losing that recipient's mail.
    def notification_email_addresses_are_valid
      invalid = notification_emails.reject { |address| address.match?(URI::MailTo::EMAIL_REGEXP) }
      return if invalid.empty?

      errors.add(:notification_email, "is not a valid email address: #{invalid.to_sentence}")
    end

    def nightly_run_days_are_weekday_numbers
      days = nightly_run_days
      unless days.is_a?(Array) && days.present? && days.all? { |d| d.is_a?(Integer) && d.between?(0, 6) }
        errors.add(:nightly_run_days, "must include at least one weekday number (0=Sun..6=Sat)")
      end
    end
  end
end
