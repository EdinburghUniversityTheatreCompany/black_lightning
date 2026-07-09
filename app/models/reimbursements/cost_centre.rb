module Reimbursements
  ##
  # A pot of money with its own budgets, admins and EUSA cost-centre code.
  # Fringe (F40) is live today; termtime (BED) becomes a second entry when the
  # portal takes over termtime payments — config, not a rewrite.
  class CostCentre
    attr_reader :key, :name, :eusa_code, :mailbox

    def initialize(key:, name:, eusa_code:, mailbox:)
      @key = key
      @name = name
      @eusa_code = eusa_code
      @mailbox = mailbox
      freeze
    end

    FRINGE = new(
      key: :fringe,
      name: "Bedlam Fringe 2026",
      eusa_code: "F40",
      mailbox: "reimbursements@bedlamfringe.co.uk"
    )

    ALL = [ FRINGE ].freeze

    def self.default
      FRINGE
    end

    def self.all
      ALL
    end
  end
end
