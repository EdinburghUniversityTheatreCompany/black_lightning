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
        sign_in grant_reimbursements_finance(users(:member))

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
        sign_in grant_reimbursements_finance(users(:member))

        @termtime = create_second_reimbursements_cost_centre
        @graph = FakeGraphClient.new
        BatchesController.graph_builder = -> { @graph }
      end

      teardown do
        BatchesController.graph_builder = -> { ::Reimbursements::GraphClient.new }
      end

      test "the stale draft is deleted from the batch's own cost centre's mailbox" do
        batch = create_reimbursements_batch(draft_message_id: "msg-1")
        create_reimbursements_expense(
          person: create_reimbursements_person, batch: batch,
          status: ::Reimbursements::Status::SUBMITTED,
          budget: create_reimbursements_budget(name: "Termtime props", cost_centre: @termtime)
        )

        post :reopen, params: { id: batch.record_id }

        assert_equal @termtime.send_mailbox, @graph.deleted_messages.last[:mailbox]
      end
    end
  end
end
