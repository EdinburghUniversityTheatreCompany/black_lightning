require "test_helper"

module Admin
  module Reimbursements
    ##
    # The places a cost centre decides where money or mail actually goes. Each
    # of these read CostCentre.default — order(:id).first — so with a second
    # centre configured they all named the wrong pot.
    #
    # The second centre is built here, not added to the fixtures: a second
    # fixture row makes CostCentre.default resolve to whichever label
    # FixtureSet.identify hashes lower and deletes the one-centre world the
    # reconcile tests pin as a business rule.
    class CostCentreMoneyPathTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      tests ReviewController

      setup do
        grant_finance_permission(users(:member))
        sign_in users(:member)

        @fringe = ::Reimbursements::CostCentre.default
        @termtime = create_second_reimbursements_cost_centre

        @graph = FakeGraphClient.new
        ReviewController.notifier_builder =
          ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre, graph: @graph) }
      end

      teardown do
        ReviewController.notifier_builder =
          ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre) }
      end

      test "a rejection email is sent from the mailbox of the claim's own cost centre" do
        payee = create_reimbursements_person(name: "Pat", email: "pat@example.com")
        claim = create_reimbursements_expense(
          person: payee,
          budget: create_reimbursements_budget(name: "Termtime props", cost_centre: @termtime)
        )

        post :reject, params: { id: claim.record_id, rejection_reason: "No receipt" }

        assert_equal @termtime.send_mailbox, @graph.send_mails.last[:mailbox]
      end

      test "each claim's rejection goes from its own centre, in one bulk gesture" do
        payee = create_reimbursements_person(name: "Pat", email: "pat@example.com")
        fringe_claim = create_reimbursements_expense(
          person: payee,
          budget: create_reimbursements_budget(name: "Fringe props", cost_centre: @fringe)
        )
        termtime_claim = create_reimbursements_expense(
          person: payee,
          budget: create_reimbursements_budget(name: "Termtime props", cost_centre: @termtime)
        )

        post :bulk_reject, params: { expense_ids: [ fringe_claim.record_id, termtime_claim.record_id ],
                                     rejection_reason: "No receipt" }

        assert_equal [ @fringe.send_mailbox, @termtime.send_mailbox ].sort,
                     @graph.send_mails.map { |mail| mail[:mailbox] }.sort
      end
    end

    ##
    # Reopening a batch deletes its stale EUSA draft — from the mailbox that
    # holds it, which is the send mailbox of the centre the batch was built for.
    class ReopenDraftMailboxTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      tests BatchesController

      setup do
        grant_finance_permission(users(:member))
        sign_in users(:member)

        @termtime = create_second_reimbursements_cost_centre
        @graph = FakeGraphClient.new
        BatchesController.graph_builder = -> { @graph }
      end

      teardown do
        BatchesController.graph_builder = -> { ::Reimbursements::GraphClient.new }
      end

      # Records which mailboxes were asked, and answers "yes, still a draft" for
      # one of them only — so a test can pin WHERE a reopen went looking, in
      # order, rather than only where it ended up.
      class DraftInOneMailbox < FakeGraphClient
        attr_reader :probed

        def initialize(holder)
          super()
          @holder = holder
          @probed = []
        end

        def draft_message?(mailbox:, message_id:)
          @probed << mailbox
          mailbox == @holder
        end
      end

      def use_graph_holding_draft_in(mailbox)
        @graph = DraftInOneMailbox.new(mailbox)
        BatchesController.graph_builder = -> { @graph }
        @graph
      end

      def batch_with(draft_message_id: "msg-1", budget: nil)
        batch = create_reimbursements_batch(draft_message_id: draft_message_id)
        create_reimbursements_expense(person: create_reimbursements_person, batch: batch,
                                      status: ::Reimbursements::Status::SUBMITTED, budget: budget)
        batch
      end

      test "the stale draft is deleted from the batch's own cost centre's mailbox" do
        use_graph_holding_draft_in(@termtime.send_mailbox)
        batch = batch_with(budget: create_reimbursements_budget(name: "Termtime props",
                                                                cost_centre: @termtime))

        post :reopen, params: { id: batch.record_id }

        assert_equal @termtime.send_mailbox, @graph.deleted_messages.last[:mailbox]
      end

      # Every batch built before this branch drafted into the DEFAULT centre's
      # mailbox whatever its claims say. GraphClient#draft_message? fails closed,
      # so guessing one mailbox and stopping turned a legacy batch into a
      # permanent "it may already have been sent — do not reopen", which is
      # untrue and, being derived from stored data, would never become true.
      test "a legacy batch whose draft is in the default mailbox is still reopenable" do
        default = ::Reimbursements::CostCentre.default
        use_graph_holding_draft_in(default.send_mailbox)
        batch = batch_with(budget: create_reimbursements_budget(name: "Termtime props",
                                                                cost_centre: @termtime))

        post :reopen, params: { id: batch.record_id }

        assert_equal [ @termtime.send_mailbox, default.send_mailbox ], @graph.probed,
                     "derived centre first, then the default"
        assert_equal default.send_mailbox, @graph.deleted_messages.last[:mailbox]
        assert_nil ::Reimbursements::Batch.find_by(id: batch.id), "the batch should have been removed"
      end

      test "a batch of only unplaced claims falls back to the default mailbox" do
        default = ::Reimbursements::CostCentre.default
        use_graph_holding_draft_in(default.send_mailbox)
        batch = batch_with(budget: nil)

        post :reopen, params: { id: batch.record_id }

        assert_equal default.send_mailbox, @graph.deleted_messages.last[:mailbox]
      end

      # The refusal has to survive: it is what stops a batch whose draft was
      # already SENT by hand in Outlook being rebuilt into a second live
      # submission. It just must not fire until every candidate has been asked.
      test "a draft in no mailbox at all still refuses the reopen" do
        use_graph_holding_draft_in("nowhere@example.invalid")
        batch = batch_with(budget: create_reimbursements_budget(name: "Termtime props",
                                                                cost_centre: @termtime))

        post :reopen, params: { id: batch.record_id }

        assert_equal 2, @graph.probed.size, "both candidates asked before refusing"
        assert_empty @graph.deleted_messages
        assert_match(/could not be confirmed as still unsent/, flash[:alert])
        assert ::Reimbursements::Batch.find_by(id: batch.id), "the batch must survive a refusal"
      end
    end
  end
end
