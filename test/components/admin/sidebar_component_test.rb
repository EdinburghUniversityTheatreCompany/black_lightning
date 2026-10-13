require "test_helper"

class Admin::SidebarComponentTest < ViewComponent::TestCase
  setup do
    @nav_items = [
      { title: "Productions", fa_icon: "fa-industry", children: [
        { title: "Shows", path: "/admin/shows", fa_icon: "fa-masks-theater" }
      ] }
    ]
  end

  def render_sidebar(current_path, nav_items: @nav_items, **options)
    render_inline Admin::SidebarComponent.new(nav_items:, current_user: users(:admin), current_path:, **options)
  end

  test "renders categories, marks the current item active and opens its category" do
    render_sidebar "/admin/shows"

    assert_selector "details[open] summary", text: /Productions/
    assert_selector "a.active[href='/admin/shows']", text: /Shows/
    assert_no_selector "details p"
  end

  # current_path is request.fullpath, so filter state arrives as a query string.
  # A character-wise prefix match would light "/admin/shows" up for "/admin/shows_archive".
  { "/admin/shows/12/edit" => true,
    "/admin/shows?q%5Bname_cont%5D=hamlet" => true,
    "/admin/shows_archive" => false }.each do |path, active|
    test "#{path} #{active ? 'marks' : 'does not mark'} the Shows item active" do
      render_sidebar path

      selector = "a.active[href='/admin/shows']"
      active ? assert_selector(selector) : assert_no_selector(selector)
    end
  end

  test "an exact item is active only on its own page" do
    nav = [ { title: "Building", fa_icon: "fa-building", children: [
      { title: "Crypt Climate", path: "/admin/climate", fa_icon: "fa-droplet", exact: true },
      { title: "Sensors", path: "/admin/climate/sensors", fa_icon: "fa-thermometer" }
    ] } ]

    render_sidebar "/admin/climate/sensors", nav_items: nav

    assert_no_selector "a.active[href='/admin/climate']"
    assert_selector "a.active[href='/admin/climate/sensors']"
  end

  test "renders a heading each time a category's group changes" do
    grouped = [ { title: "Finance", fa_icon: "fa-money-bill-wave", children: [
      { group: "Pay claims", title: "Review claims", path: "/admin/reimbursements/review", fa_icon: "fa-clipboard-check" },
      { group: "Pay claims", title: "All claims", path: "/admin/reimbursements/expense_edits", fa_icon: "fa-pen-to-square" },
      { group: "Setup", title: "People", path: "/admin/reimbursements/people", fa_icon: "fa-address-book" }
    ] } ]

    render_sidebar "/admin/reimbursements/review", nav_items: grouped

    headings = page.all("details p").map(&:text)
    assert_equal [ "Pay claims", "Setup" ], headings
  end

  # The import wizards sit under no item's path.
  test "a category stays open on a page that belongs to it but sits under no item" do
    finance = [ { title: "Finance", fa_icon: "fa-money-bill-wave", children: [
      { group: "Budgets", title: "Budgets", path: "/admin/reimbursements/budgets", fa_icon: "fa-sack-dollar" }
    ] } ]

    render_sidebar "/admin/reimbursements/budget_import", nav_items: finance

    assert_selector "details[open]"
  end

  # --- Finance selectors: the year and cost centre must survive a sidebar click ---

  def scoped_items
    [ { title: "Finance", fa_icon: "fa-money-bill-wave", children: [
      { group: "Budgets", title: "Budgets", path: "/admin/reimbursements/budgets",
        fa_icon: "fa-sack-dollar", scoped: true },
      { group: "Budgets", title: "Import", path: "/admin/reimbursements/budget_import?cost_centre_id=7",
        fa_icon: "fa-file-import", scoped: true },
      { title: "My Claims", path: "/admin/reimbursements/expenses", fa_icon: "fa-file-invoice" }
    ] } ]
  end

  def render_scoped(scope_params, nav_items: scoped_items)
    render_sidebar "/admin/reimbursements/budgets", nav_items:, scope_params:
  end

  test "a scoped item carries the year and cost centre the operator is on" do
    render_scoped({ "year" => "fringe-2027", "cost_centre" => "termtime" })

    assert_selector "a[href*='year=fringe-2027'][href*='cost_centre=termtime']", text: /Budgets/
  end

  test "an unscoped item is left bare" do
    render_scoped({ "year" => "fringe-2027" })

    assert_selector "a[href='/admin/reimbursements/expenses']", text: /My Claims/
  end

  test "nothing is appended when no selector is set" do
    render_scoped({})

    assert_selector "a[href='/admin/reimbursements/budgets']", text: /Budgets/
  end

  # An explicit "All" (cost_centre=) is a choice too: carried, so the home
  # centre does not come back on the next screen. A blank year means nothing.
  test "an explicit All cost centre is carried, a blank year is not" do
    render_scoped({ "year" => "", "cost_centre" => "" })

    assert_selector "a[href='/admin/reimbursements/budgets?cost_centre=']", text: /Budgets/
  end

  # Only the two selectors: carrying ?search= or ?page= would filter another screen.
  test "other query parameters are not carried" do
    render_scoped({ "year" => "fringe-2027", "search" => "hamlet", "page" => "3" })

    assert_no_selector "a[href*='search=hamlet']"
    assert_no_selector "a[href*='page=3']"
  end

  test "an item's own query string wins over the carried one" do
    render_scoped({ "cost_centre" => "termtime", "year" => "fringe-2027" })

    assert_selector "a[href*='cost_centre_id=7'][href*='year=fringe-2027']", text: /Import/
    assert_no_selector "a[href*='cost_centre=termtime']", text: /Import/
  end

  # "financial_year=" contains "year=": the query must be parsed, not substring-matched.
  test "a parameter merely containing a selector's name does not block it" do
    items = scoped_items
    items.first[:children].first[:path] = "/admin/reimbursements/budgets?financial_year=9"
    render_scoped({ "year" => "fringe-2027" }, nav_items: items)

    assert_selector "a[href*='financial_year=9'][href*='year=fringe-2027']", text: /Budgets/
  end

  test "marking an item active still works once its href carries a selector" do
    render_scoped({ "year" => "fringe-2027" })

    assert_selector "a.active[href*='/admin/reimbursements/budgets']", text: /Budgets/
  end
end
