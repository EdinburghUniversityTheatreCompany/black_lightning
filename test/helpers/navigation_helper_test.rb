require "test_helper"

class NavigationHelperTest < ActionView::TestCase
  include ReimbursementsTestHelpers

  def current_ability
    @current_ability ||= Ability.new(@current_user)
  end

  # ActionView::TestCase skips CanCanCan's Railtie, so delegate can?/cannot? as User does.
  def can?(...)
    current_ability.can?(...)
  end

  def cannot?(...)
    current_ability.cannot?(...)
  end

  setup do
    @current_user = users(:committee)
  end

  def finance_category
    admin_navbar_items.find { |category| category[:title] == "Finance" }
  end

  def my_reimbursements_category
    admin_navbar_items.find { |category| category[:title] == "My Reimbursements" }
  end

  test "the nine finance-gated links are hidden without the finance permission" do
    # A category with no visible children is dropped.
    assert_nil finance_category
  end

  test "every finance-gated link appears with the finance permission" do
    grant_finance_permission(@current_user)

    gated_titles = [ "Finance home", "Review claims", "All claims", "Build batch", "Batches", "Budgets",
                     "Overview", "Areas", "Forecast revisions", "Reconcile", "Ledger",
                     "Exports", "People", "Financial years", "Cost centres",
                     "Email & integrations" ]

    titles = finance_category[:children].map { |child| child[:title] }

    gated_titles.each { |title| assert_includes titles, title }
  end

  # Every link below Finance home needs a group, or it renders under whichever heading precedes it.
  test "the finance links are grouped by the job they belong to, weekly work first" do
    grant_finance_permission(@current_user)

    children = finance_category[:children]

    assert_equal "Finance home", children.first[:title]
    assert_nil children.first[:group]

    below_home = children.drop(1)
    assert_equal [ "Pay claims", "Budgets", "EUSA ledger", "Setup" ],
                 below_home.map { |child| child[:group] }.uniq
    ungrouped = below_home.reject { |child| child[:group].present? }
    assert_empty ungrouped, "a finance link with no group: #{ungrouped.inspect}"
  end

  # The namespace root is a prefix of every finance path, so it needs exact: true.
  test "Finance home matches its own page only" do
    grant_finance_permission(@current_user)

    home = finance_category[:children].find { |child| child[:title] == "Finance home" }

    assert_equal admin_reimbursements_root_path, home[:path]
    assert home[:exact], "Finance home would light up on every finance screen"
  end

  test "the producer portal permission alone does not reveal the finance-gated links" do
    grant_producer_permission(@current_user)

    assert_nil finance_category

    titles = my_reimbursements_category[:children].map { |child| child[:title] }
    assert_includes titles, "My Claims"
    assert_includes titles, "Payment Details"
    assert_includes titles, "My Budgets"
  end
end
