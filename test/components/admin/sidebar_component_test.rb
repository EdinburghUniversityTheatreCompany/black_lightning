require "test_helper"

class Admin::SidebarComponentTest < ViewComponent::TestCase
  setup do
    @nav_items = [
      { title: "Productions", fa_icon: "fa-industry", children: [
        { title: "Shows", path: "/admin/shows", fa_icon: "fa-masks-theater" }
      ] }
    ]
    @user = users(:admin)
  end

  test "renders navigation categories" do
    render_inline Admin::SidebarComponent.new(nav_items: @nav_items, current_user: @user, current_path: "/admin/shows")
    assert_selector "summary", text: /Productions/
    assert_selector "a[href='/admin/shows']", text: /Shows/
  end

  test "marks active item" do
    render_inline Admin::SidebarComponent.new(nav_items: @nav_items, current_user: @user, current_path: "/admin/shows")
    assert_selector "a.active[href='/admin/shows']"
  end

  test "marks category as open when child is active" do
    render_inline Admin::SidebarComponent.new(nav_items: @nav_items, current_user: @user, current_path: "/admin/shows")
    assert_selector "details[open]"
  end

  test "marks an item active on its own child pages" do
    render_inline Admin::SidebarComponent.new(nav_items: @nav_items, current_user: @user,
                                              current_path: "/admin/shows/12/edit")
    assert_selector "a.active[href='/admin/shows']"
  end

  # current_path is request.fullpath, and this app keeps filter state in the URL,
  # so every admin index arrives here with a query string attached.
  test "marks an item active when the URL carries filter state" do
    render_inline Admin::SidebarComponent.new(nav_items: @nav_items, current_user: @user,
                                              current_path: "/admin/shows?q%5Bname_cont%5D=hamlet")
    assert_selector "a.active[href='/admin/shows']"
  end

  # A character-wise prefix match lights "/admin/shows" up for a sibling route
  # that merely starts with the same letters.
  test "does not mark an item active for a sibling sharing its prefix" do
    render_inline Admin::SidebarComponent.new(nav_items: @nav_items, current_user: @user,
                                              current_path: "/admin/shows_archive")
    assert_no_selector "a.active[href='/admin/shows']"
  end

  test "an exact item is active only on its own page" do
    nav = [ { title: "Building", fa_icon: "fa-building", children: [
      { title: "Crypt Climate", path: "/admin/climate", fa_icon: "fa-droplet", exact: true },
      { title: "Sensors", path: "/admin/climate/sensors", fa_icon: "fa-thermometer" }
    ] } ]

    render_inline Admin::SidebarComponent.new(nav_items: nav, current_user: @user,
                                              current_path: "/admin/climate/sensors")

    assert_no_selector "a.active[href='/admin/climate']"
    assert_selector "a.active[href='/admin/climate/sensors']"
  end

  # A long category is broken into the jobs it serves, with a heading each time
  # the group changes. One level of nesting, so every link stays one click away.
  test "renders a heading each time a category's group changes" do
    grouped = [ { title: "Finance", fa_icon: "fa-money-bill-wave", children: [
      { group: "Pay claims", title: "Review claims", path: "/admin/reimbursements/review", fa_icon: "fa-clipboard-check" },
      { group: "Pay claims", title: "All claims", path: "/admin/reimbursements/expense_edits", fa_icon: "fa-pen-to-square" },
      { group: "Setup", title: "People", path: "/admin/reimbursements/people", fa_icon: "fa-address-book" }
    ] } ]

    render_inline Admin::SidebarComponent.new(nav_items: grouped, current_user: @user,
                                              current_path: "/admin/reimbursements/review")

    headings = page.all("details p").map(&:text)
    assert_equal [ "Pay claims", "Setup" ], headings
  end

  # The two import wizards and the workbook download sit under no item's path,
  # so the whole category used to collapse exactly where the flow is longest.
  test "a category stays open on a page that belongs to it but sits under no item" do
    finance = [ { title: "Finance", fa_icon: "fa-money-bill-wave", children: [
      { group: "Budgets", title: "Budgets", path: "/admin/reimbursements/budgets", fa_icon: "fa-sack-dollar" }
    ] } ]

    render_inline Admin::SidebarComponent.new(nav_items: finance, current_user: @user,
                                              current_path: "/admin/reimbursements/budget_import")

    assert_selector "details[open]"
  end

  test "a category with no group headings renders none" do
    render_inline Admin::SidebarComponent.new(nav_items: @nav_items, current_user: @user,
                                              current_path: "/admin/shows")

    assert_no_selector "details p"
  end

  # --- The finance selectors ----------------------------------------------
  # A year or cost centre picked on one finance screen was dropped by every
  # sidebar click: each nav href was bare, so the next screen silently reverted
  # to the active year and every centre.

  def scoped_items
    [ { title: "Finance", fa_icon: "fa-money-bill-wave", children: [
      { group: "Budgets", title: "Budgets", path: "/admin/reimbursements/budgets",
        fa_icon: "fa-sack-dollar", scoped: true },
      { group: "Budgets", title: "Import", path: "/admin/reimbursements/budget_import?cost_centre_id=7",
        fa_icon: "fa-file-import", scoped: true },
      { title: "My Claims", path: "/admin/reimbursements/expenses", fa_icon: "fa-file-invoice" }
    ] } ]
  end

  def render_scoped(scope_params)
    render_inline Admin::SidebarComponent.new(
      nav_items: scoped_items, current_user: @user,
      current_path: "/admin/reimbursements/budgets", scope_params: scope_params
    )
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

  # Only the two selectors, never the page's other filter state: a ?search= or
  # a ?page= carried onto another screen would filter it by something the
  # operator never typed there.
  test "other query parameters are not carried" do
    render_scoped({ "year" => "fringe-2027", "search" => "hamlet", "page" => "3" })

    assert_no_selector "a[href*='search=hamlet']"
    assert_no_selector "a[href*='page=3']"
  end

  # An item stating a scope of its own is stating it on purpose.
  test "an item's own query string wins over the carried one" do
    render_scoped({ "cost_centre" => "termtime", "year" => "fringe-2027" })

    assert_selector "a[href*='cost_centre_id=7'][href*='year=fringe-2027']", text: /Import/
    assert_no_selector "a[href*='cost_centre=termtime']", text: /Import/
  end

  # "financial_year=" contains "year=", so a substring test in either direction
  # gets one of the two coordinates wrong. The query is parsed instead.
  test "a parameter merely containing a selector's name does not block it" do
    items = scoped_items
    items.first[:children].first[:path] = "/admin/reimbursements/budgets?financial_year=9"
    render_inline Admin::SidebarComponent.new(
      nav_items: items, current_user: @user,
      current_path: "/admin/reimbursements/budgets", scope_params: { "year" => "fringe-2027" }
    )

    assert_selector "a[href*='financial_year=9'][href*='year=fringe-2027']", text: /Budgets/
  end

  test "marking an item active still works once its href carries a selector" do
    render_scoped({ "year" => "fringe-2027" })

    assert_selector "a.active[href*='/admin/reimbursements/budgets']", text: /Budgets/
  end
end
