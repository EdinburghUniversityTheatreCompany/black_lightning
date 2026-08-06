module Reimbursements
  ##
  # The reimbursements receipt mailbox. All the Graph plumbing lives in
  # Graph::MailboxClient, shared with the climate CSV mailbox; this only pins
  # the default address to the cost centre's own receive mailbox and keeps the
  # constant names every rescue in this subsystem already uses.
  class MailboxClient < ::Graph::MailboxClient
    Error = ::GraphAuth::Error
    AuthError = ::GraphAuth::AuthError
    NotFoundError = ::GraphAuth::NotFoundError

    def initialize(mailbox: CostCentre.default&.receive_mailbox, settings: ::Graph::Settings,
                   http: nil, clock: nil)
      super
    end
  end
end
