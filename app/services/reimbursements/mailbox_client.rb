module Reimbursements
  # The reimbursements receipt mailbox: Graph::MailboxClient defaulting to the cost centre's
  # receive mailbox, plus the error names this subsystem rescues.
  class MailboxClient < ::Graph::MailboxClient
    Error = ::GraphAuth::Error
    AuthError = ::GraphAuth::AuthError
    NotFoundError = ::GraphAuth::NotFoundError

    def initialize(mailbox: CostCentre.default&.receive_mailbox, settings: ::Graph::Settings,
                   http: nil, clock: nil, sleeper: nil)
      super
    end
  end
end
