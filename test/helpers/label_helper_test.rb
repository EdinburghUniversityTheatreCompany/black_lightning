require "test_helper"

BASE_BADGE_CLASSES = "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"

class LabelHelperTest < ActionView::TestCase
  test "sanitizes html" do
    message = "<faketag>Finbar<div> the <p></p>Viking"
    label = generate_label("bg-info", message)
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-info/15 text-info\">Finbar<div> the <p></p>Viking</div></span>", label
  end

  test "returns label" do
    label = generate_label("bg-danger", "It's dangerous to go alone!")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">It's dangerous to go alone!</span>", label
  end

  test "returns label with float-right" do
    label = generate_label("bg-success", "You did it!", true)
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-success/15 text-success float-right\">You did it!</span>", label
  end

  test "bg-warning maps to semantic warning classes" do
    label = generate_label("bg-warning", "Watch out!")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-warning/15 text-warning\">Watch out!</span>", label
  end

  test "bg-light maps to gray classes" do
    label = generate_label("bg-light", "Light label")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-gray-100 text-gray-800\">Light label</span>", label
  end

  test "bg-info maps to semantic info classes" do
    label = generate_label("bg-info", "Info label")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-info/15 text-info\">Info label</span>", label
  end

  test "rounded adds rounded-full class" do
    label = generate_label("bg-danger", "Rounded!", false, true)
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger rounded-full\">Rounded!</span>", label
  end

  test "pull_right and rounded can be combined" do
    label = generate_label("bg-success", "Both!", true, true)
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-success/15 text-success rounded-full float-right\">Both!</span>", label
  end

  test "nil label_class produces badge with no extra class" do
    label = generate_label(nil, "No class")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} \">No class</span>", label
  end

  class ProposalLabelsTest < ActionView::TestCase
    setup do
      @call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.current.advance(days: 5), question_count: 3)
      @proposal = FactoryBot.create(:proposal, :with_team_members, call: @call)
    end

    test "labels for successful proposal with debtors" do
      @proposal.status = :successful
      _debt = FactoryBot.create(:staffing_debt, user: @proposal.users.first, due_by: @call.editing_deadline.advance(days: -1))
      expected_labels = "<span class=\"#{BASE_BADGE_CLASSES} bg-success/15 text-success\">Successful</span>\n<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Has Debtors</span>"

      assert_equal expected_labels, proposal_labels(@proposal, false)
    end

    test "labels for rejected proposal that was late with pull right" do
      @proposal.late = true
      @proposal.status = :rejected

      expected_labels = "<div class=\"float-right\"><span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Rejected</span>\n<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Late</span></div>"

      assert_equal expected_labels, proposal_labels(@proposal, true)
    end

    test "labels for proposal awaiting approval with debtors that was late" do
      @proposal.status = :awaiting_approval
      @proposal.late = true
      _debt = FactoryBot.create(:staffing_debt, user: @proposal.users.first, due_by: @call.editing_deadline.advance(days: -1))

      expected_labels = "<span class=\"#{BASE_BADGE_CLASSES} bg-warning/15 text-warning\">Awaiting Approval</span>\n<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Late</span>\n<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Has Debtors</span>"

      assert_equal expected_labels, proposal_labels(@proposal, false)
    end

    test "labels for approved proposal" do
      @proposal.status = :approved

      expected_labels = "<span class=\"#{BASE_BADGE_CLASSES} bg-info/15 text-info\">Approved</span>"

      assert_equal expected_labels, proposal_labels(@proposal, false)
    end

    test "labels for unsuccessful proposal with pull right" do
      @proposal.status = :unsuccessful

      expected_labels = "<div class=\"float-right\"><span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Unsuccessful</span></div>"

      assert_equal expected_labels, proposal_labels(@proposal, true)
    end
  end
end
