module Admin
  module Reimbursements
    ##
    # In-app setup & scaling runbook for the finance team + IT: the manual Azure /
    # mailbox / SharePoint steps the app can't do itself (adding a cost centre's
    # mailboxes, scoping the Graph app to them, where operator emails send from).
    # Read-only; finance-gated like the rest of the operator tooling.
    class HelpController < FinanceController
      def show
        @title = "Reimbursements — setup & scaling guide"
      end
    end
  end
end
