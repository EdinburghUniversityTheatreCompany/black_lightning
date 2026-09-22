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

      # How many recent sends the page lists. Enough to cover a run-day or two
      # of reminders without turning a health dashboard into a mail archive;
      # the search below is how you reach further back.
      SEND_LOG_LIMIT = 50

      def load_cost_centres
        @title = "Integration Status"
        @cost_centres = ::Reimbursements::CostCentre.order(:name)
        load_send_log
      end

      # What the portal has emailed, and to whom.
      #
      # The page could say whether Graph was reachable and when each centre's
      # nightly last completed, and nothing about what was actually sent — so
      # "did this person get their reminder?" had no answer short of asking
      # them. ?recipient= searches one address, which is the form the question
      # is always asked in.
      def load_send_log
        @recipient_query = params[:recipient].to_s.strip
        @sends =
          if @recipient_query.present?
            ::Reimbursements::NotificationLog.for_recipient(@recipient_query)
                                             .recent_first.includes(:cost_centre)
                                             .limit(SEND_LOG_LIMIT).to_a
          else
            ::Reimbursements::NotificationLog.recent(limit: SEND_LOG_LIMIT,
                                                     cost_centre: selected_cost_centre).to_a
          end
        # Per-run counts: one line per day and kind, which is how the nightly
        # actually happens — a run-day sends a batch of one kind to several
        # people, and the count is the thing that looks wrong when it is wrong.
        @send_counts = @sends.group_by { |log| [ log.sent_at.to_date, log.kind ] }
                             .transform_values(&:size)
                             .sort_by { |(date, kind), _| [ date, kind ] }.reverse
        # The page has to say how far back it can see. "Nothing before this log
        # existed" is unanswerable from the screen; a date is checkable against
        # the run the operator is asking about.
        @send_log_since = ::Reimbursements::NotificationLog.minimum(:sent_at)
        @send_log_limit = SEND_LOG_LIMIT
      end

      def graph
        @graph ||= graph_builder.call
      end

      # Graph is the only integration to probe today. This stays an ARRAY so
      # adding the next one is a one-line change, and each probe is rescued on
      # its own so one dead service renders a failed row rather than 500ing the
      # page. (That explanation used to sit in the view's visible copy — a code
      # comment rendered to finance users; keep it here.)
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
