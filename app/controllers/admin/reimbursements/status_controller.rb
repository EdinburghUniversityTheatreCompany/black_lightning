module Admin
  module Reimbursements
    ##
    # Section-wide health dashboard for the reimbursements integrations, widening
    # the Settings per-cost-centre access-check into one view of the external
    # services the finance flows depend on: Microsoft Graph (email drafts +
    # SharePoint).
    #
    # The live probes are ON-DEMAND (a "Run checks" button POSTs to #run), never
    # on page load, so an idle visit doesn't wait on Microsoft. Each probe is
    # rescued independently so one failing service never 500s the page — it just
    # renders a failed row with the message.
    #
    # The last-nightly-run date per cost centre is a plain DB read (no external
    # call), so it is always shown, on both #show and #run.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class StatusController < FinanceController
      # Injection seam for tests: the app-only Graph client (token probe).
      class_attribute :graph_builder, default: -> { ::Reimbursements::GraphClient.new }

      # One row of the integration-check results.
      Check = Struct.new(:label, :status, :detail, keyword_init: true)

      before_action :load_cost_centres

      def show
      end

      # Run the live probes and render the results (a Turbo-stream update of the
      # results region, or a full re-render for a non-Turbo request).
      def run
        @checks = run_checks
        respond_to do |format|
          format.turbo_stream
          format.html { render :show }
        end
      end

      private

      # The view reads each role's members directly (not notification_role_empty?)
      # because it needs the list anyway for the missing-permission line; the
      # preload keeps that off the N+1 path.
      def load_cost_centres
        @title = "Integration Status"
        @cost_centres = ::Reimbursements::CostCentre.includes(notification_role: :users).order(:name)
      end

      # Who can actually open the finance screens. A notification role is
      # deliberately NOT filtered to these users -- the permission grid and the
      # mailing list are separate by design -- so a member of the role without
      # the permission is surfaced rather than silently dropped: they would be
      # emailed about claims they cannot open.
      def finance_user_ids
        @finance_user_ids ||=
          Admin::Permission.where(action: "manage", subject_class: "reimbursements_finance")
                           .includes(roles: :users)
                           .flat_map(&:roles).flat_map(&:users).map(&:id).to_set
      end
      helper_method :finance_user_ids

      def graph
        @graph ||= graph_builder.call
      end

      def run_checks
        [ graph_check ]
      end

      # Acquire an app-only Graph token (see GraphClient#check_reachable).
      def graph_check
        return graph_skip unless ::Reimbursements::Settings.mailbox_configured?

        graph.check_reachable
        Check.new(label: "Microsoft Graph", status: :ok, detail: "Reachable: acquired an app token.")
      rescue StandardError => e
        Check.new(label: "Microsoft Graph", status: :fail,
                  detail: "#{e.message}. The Azure app's client secret may have expired. Contact IT " \
                          "to rotate it (it's a server credential, not set here).")
      end

      def graph_skip
        Check.new(label: "Microsoft Graph", status: :skip,
                  detail: "No Azure credentials configured yet.")
      end
    end
  end
end
