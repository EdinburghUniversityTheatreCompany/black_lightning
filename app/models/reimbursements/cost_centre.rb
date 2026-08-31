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
#  nightly_run_days              :string(255)      default("[2,4]"), not null
#  receive_mailbox               :string(255)      not null
#  send_mailbox                  :string(255)      not null
#  sharepoint_site_url           :string(255)
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  notification_role_id          :integer
#  sharepoint_bacs_drive_id      :string(255)
#  sharepoint_bacs_folder_id     :string(255)
#  sharepoint_receipts_drive_id  :string(255)
#  sharepoint_receipts_folder_id :string(255)
#
# Indexes
#
#  index_reimbursements_cost_centres_on_key                   (key) UNIQUE
#  index_reimbursements_cost_centres_on_notification_role_id  (notification_role_id)
#
# Foreign Keys
#
#  fk_rails_...  (notification_role_id => roles.id)
#
module Reimbursements
  ##
  # A pot of money with its own budgets, admins, EUSA cost-centre code and
  # mailboxes. Fringe (F40) is live; termtime (BED) becomes a second row when the
  # portal takes over termtime payments — a row, not a rewrite.
  #
  # An ActiveRecord model rather than a frozen in-code value, because the
  # business manager edits these operational settings in the UI (Settings). Each
  # cost centre has its own +receive_mailbox+ (email-in) and +send_mailbox+
  # (draft / send-from) — they may differ. Table inferred as
  # reimbursements_cost_centres.
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

    # Who gets this centre's operator reminders. A Role, so a committee handover
    # is the same gesture as every other handover and the members are real
    # accounts that cannot rot into someone who has left. These finance roles are
    # deliberately NOT part of the annual Role#archive sweep.
    #
    # Optional at the association level; the requirement is the explicit
    # validation below, so the error hangs off :notification_role -- the
    # attribute the Settings form labels -- rather than off belongs_to's own
    # message.
    belongs_to :notification_role, class_name: "Role", optional: true

    # The +key+ is the URL slug (`param: :key`, `find_by!(key:)`), so it must be
    # URL-safe. Derive it from the name by default (create form leaves it blank),
    # and enforce the slug shape whether typed or derived.
    before_validation :derive_key_from_name

    validates :key, presence: true, uniqueness: true
    validates :key, format: { with: /\A[a-z0-9-]+\z/,
                              message: "may only contain lowercase letters, numbers and hyphens" },
                    allow_blank: true
    validates :name, :eusa_code, :receive_mailbox, :send_mailbox, presence: true
    # Required: a cost centre whose reminders reach nobody leaves a producer
    # waiting indefinitely with nothing on screen to explain it. The Settings
    # forms collect it on both create and update.
    validates :notification_role, presence: true
    # Prevents a duplicate-mailbox/code misconfiguration once a second cost
    # centre is seeded — e.g. two rows accidentally sharing one receive
    # mailbox would make MailboxPollJob attribute every email-in receipt to
    # whichever cost centre happens to be polled first.
    validates :eusa_code, uniqueness: true
    validates :receive_mailbox, uniqueness: { case_sensitive: false }
    validates :send_mailbox, uniqueness: { case_sensitive: false }
    # No format check existed anywhere on this write path — a mistyped
    # mailbox would silently misconfigure email-in / draft-sending, and
    # eusa_recipient feeds straight into the BACS draft's "to" address.
    validates :receive_mailbox, :send_mailbox, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :eusa_recipient, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
    validate :nightly_run_days_are_weekday_numbers

    # The primary cost centre (Fringe today). Multi-cost-centre flows iterate
    # .all; .default is for the single-cost-centre call sites that predate the
    # per-cost-centre work (mailbox poll, mailbox client).
    def self.default
      order(:id).first
    end

    # Where renamed receipts land, or nil until configured (Settings).
    def receipts_folder
      folder(sharepoint_receipts_drive_id, sharepoint_receipts_folder_id)
    end

    # Where the BACS xlsx is backed up, or nil until configured.
    def bacs_folder
      folder(sharepoint_bacs_drive_id, sharepoint_bacs_folder_id)
    end

    # Build Batch needs both SharePoint destinations before it can offload files.
    # Whether Build Batch can offload files: the drive+folder ids alone locate
    # the destination (the site URL is only needed to BROWSE for them), so this
    # is the upload-capability gate BatchProcessor keys off.
    def sharepoint_configured?
      receipts_folder.present? && bacs_folder.present?
    end

    # Stricter, for the settings "SharePoint set" badge: also requires the site
    # URL. Without it the browse/verify flow is broken and the stored folder
    # ids can silently belong to a since-changed site — so an all-green badge
    # would misrepresent a half-configured (or repointed) setup.
    def sharepoint_fully_configured?
      sharepoint_configured? && sharepoint_site_url.present?
    end

    # The Graph addressing form of the configured SharePoint site
    # ("tenant.sharepoint.com:/sites/Finance"), or nil if no site URL is set or
    # it doesn't parse. Used to browse the site (Sites.Selected can't search, so
    # it addresses a granted site by path) and to fill the per-site grant command
    # on the Settings page.
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

    # No role, or a role nobody is in -- either way this centre's reminders would
    # reach nobody. The nightly warns and refuses to record the run-day rather
    # than going quiet, and the Integration Status page badges it.
    def notification_role_empty?
      notification_role.nil? || notification_role.users.empty?
    end

    # --- Copy derived from this cost centre -------------------------------
    # Every producer- and operator-facing email, filename and sign-off reads
    # its wording from here rather than hardcoding "Bedlam Fringe", so a second
    # cost centre gets correct copy the moment its row exists. +subject_prefix+
    # is the single source every subject line shares.

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

    # Where a submitter should write with a question. The receive mailbox is
    # the address email-in already answers, so it is the one guaranteed to be
    # monitored for this cost centre.
    def contact_email
      receive_mailbox
    end

    # Filename-safe form of the name, for the BACS spreadsheet sent to EUSA.
    def slug
      name.to_s.parameterize
    end

    # --- Nightly auto-submit scheduling -----------------------------------
    # The last-completed run date is stored on the row itself.
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

    # Auto-fill the URL slug from the name when the operator didn't type one
    # (the create form's manual "key" field lives in a collapsed Advanced
    # section). An explicit key is left untouched so it can be overridden.
    def derive_key_from_name
      self.key = name.to_s.parameterize if key.blank? && name.present?
    end

    def nightly_run_days_are_weekday_numbers
      days = nightly_run_days
      unless days.is_a?(Array) && days.present? && days.all? { |d| d.is_a?(Integer) && d.between?(0, 6) }
        errors.add(:nightly_run_days, "must include at least one weekday number (0=Sun..6=Sat)")
      end
    end
  end
end
