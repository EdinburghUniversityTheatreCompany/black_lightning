require "test_helper"

class LabelHelperTest < ActionView::TestCase
  test "sanitizes html" do
    message = "<faketag>Finbar<div> the <p></p>Viking"
    label = generate_label("bg-info", message)
    assert_equal '<span class="badge bg-info text-dark">Finbar<div> the <p></p>Viking</div></span>', label
  end

  test "returns label" do
    label = generate_label("bg-danger", "It's dangerous to go alone!")
    assert_equal '<span class="badge bg-danger">It\'s dangerous to go alone!</span>', label
  end

  test "returns label with float-right" do
    label = generate_label("bg-success", "You did it!", true)
    assert_equal '<span class="badge bg-success float-right">You did it!</span>', label
  end

  test "bg-warning gets text-dark class" do
    label = generate_label("bg-warning", "Watch out!")
    assert_equal '<span class="badge bg-warning text-dark">Watch out!</span>', label
  end

  test "bg-light gets text-dark class" do
    label = generate_label("bg-light", "Light label")
    assert_equal '<span class="badge bg-light text-dark">Light label</span>', label
  end

  test "bg-info gets text-dark class" do
    label = generate_label("bg-info", "Info label")
    assert_equal '<span class="badge bg-info text-dark">Info label</span>', label
  end

  test "rounded adds rounded-pill class" do
    label = generate_label("bg-danger", "Rounded!", false, true)
    assert_equal '<span class="badge bg-danger rounded-pill">Rounded!</span>', label
  end

  test "pull_right and rounded can be combined" do
    label = generate_label("bg-success", "Both!", true, true)
    assert_equal '<span class="badge bg-success rounded-pill float-right">Both!</span>', label
  end

  test "nil label_class produces badge with no extra class" do
    label = generate_label(nil, "No class")
    assert_equal '<span class="badge ">No class</span>', label
  end

  class ProposalLabelsTest < ActionView::TestCase
    setup do
      @call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.current.advance(days: 5), question_count: 3)
      @proposal = FactoryBot.create(:proposal, :with_team_members, call: @call)
    end

    test "labels for successful proposal with debtors" do
      @proposal.status = :successful
      _debt = FactoryBot.create(:staffing_debt, user: @proposal.users.first, due_by: @call.editing_deadline.advance(days: -1))
      expected_labels = "<span class=\"badge bg-success\">Successful</span>\n<span class=\"badge bg-danger\">Has Debtors</span>"

      assert_equal expected_labels, proposal_labels(@proposal, false)
    end

    test "labels for rejected proposal that was late with pull right" do
      @proposal.late = true
      @proposal.status = :rejected

      expected_labels = "<div class=\"float-right\"><span class=\"badge bg-danger\">Rejected</span>\n<span class=\"badge bg-danger\">Late</span></div>"

      assert_equal expected_labels, proposal_labels(@proposal, true)
    end

    test "labels for proposal awaiting approval with debtors that was late" do
      @proposal.status = :awaiting_approval
      @proposal.late = true
      _debt = FactoryBot.create(:staffing_debt, user: @proposal.users.first, due_by: @call.editing_deadline.advance(days: -1))

      expected_labels = "<span class=\"badge bg-warning text-dark\">Awaiting Approval</span>\n<span class=\"badge bg-danger\">Late</span>\n<span class=\"badge bg-danger\">Has Debtors</span>"

      assert_equal expected_labels, proposal_labels(@proposal, false)
    end

    test "labels for approved proposal" do
      @proposal.status = :approved

      expected_labels = '<span class="badge bg-info text-dark">Approved</span>'

      assert_equal expected_labels, proposal_labels(@proposal, false)
    end

    test "labels for unsuccessful proposal with pull right" do
      @proposal.status = :unsuccessful

      expected_labels = "<div class=\"float-right\"><span class=\"badge bg-danger\">Unsuccessful</span></div>"

      assert_equal expected_labels, proposal_labels(@proposal, true)
    end
  end
end
