module Admin
  module Reimbursements
    ##
    # Section-wide health dashboard for the reimbursements integrations, widening
    # the Settings per-cost-centre access-check into one view of the external
    # services the finance flows depend on: Airtable (the data store), Microsoft
    # Graph (email drafts + SharePoint) and Gemini (AI expense checking).
    #
    # The live probes are ON-DEMAND (a "Run checks" button POSTs to #run), never
    # on page load, so an idle visit doesn't burn Airtable free-plan quota or wait
    # on Microsoft. Each probe is rescued independently so one failing service
    # never 500s the page — it just renders a failed row with the message.
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

      def show
        @title = "Integration Status"
        @cost_centres = ::Reimbursements::CostCentre.order(:name)
      end

      # Run the live probes and render the results (a Turbo-stream update of the
      # results region, or a full re-render for a non-Turbo request).
      def run
        @title = "Integration Status"
        @cost_centres = ::Reimbursements::CostCentre.order(:name)
        @checks = run_checks
        respond_to do |format|
          format.turbo_stream
          format.html { render :show }
        end
      end

      private

      def graph
        @graph ||= graph_builder.call
      end

      def run_checks
        [ airtable_check, graph_check, gemini_check ]
      end

      # A minimal Airtable read through the Store — reaching the budgets list is
      # enough to prove the PAT + base are good.
      def airtable_check
        count = store.budgets.size
        Check.new(label: "Airtable", status: :ok, detail: "Reachable — read #{count} budget(s).")
      rescue StandardError => e
        Check.new(label: "Airtable", status: :fail,
                  detail: "#{e.message}. This needs the development team — the Airtable token or " \
                          "base id (a server credential, not something you can change here).")
      end

      # Acquire an app-only Graph token (see GraphClient#check_reachable).
      def graph_check
        return graph_skip unless ::Reimbursements::Settings.mailbox_configured?

        graph.check_reachable
        Check.new(label: "Microsoft Graph", status: :ok, detail: "Reachable — acquired an app token.")
      rescue StandardError => e
        Check.new(label: "Microsoft Graph", status: :fail,
                  detail: "#{e.message}. The Azure app's client secret may have expired — contact the " \
                          "development team to rotate it (it's a server credential, not set here).")
      end

      def graph_skip
        Check.new(label: "Microsoft Graph", status: :skip,
                  detail: "No Azure credentials configured yet.")
      end

      # Config presence only: a live Gemini call costs a request per receipt, so
      # the dashboard just confirms the API key is set (the AI checker degrades to
      # an "error" verdict at call time if it later fails).
      def gemini_check
        if ::Reimbursements::Settings.gemini_api_key.present?
          Check.new(label: "Gemini (AI checker)", status: :ok, detail: "API key configured.")
        else
          Check.new(label: "Gemini (AI checker)", status: :skip,
                    detail: "No API key set — AI checks are disabled.")
        end
      end
    end
  end
end
