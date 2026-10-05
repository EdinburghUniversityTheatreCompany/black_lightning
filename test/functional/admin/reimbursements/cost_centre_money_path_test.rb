require "test_helper"

module Admin
  module Reimbursements
    ##
    # Where a cost centre decides where money or mail goes. The second centre is
    # built in-test, never a fixture: a second fixture row changes CostCentre.default.
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
    # Reopening a batch deletes its stale EUSA draft from the send mailbox of the
    # centre the batch was built for.
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

      # Holds the draft in one mailbox only, and records which were asked in order.
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

      # Legacy batches drafted into the DEFAULT centre's mailbox, and
      # draft_message? fails closed, so probing one mailbox would refuse them for ever.
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

      # The refusal stops a batch already sent by hand being resubmitted; it must
      # survive, but only once every candidate mailbox has been asked.
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
