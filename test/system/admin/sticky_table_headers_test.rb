require "application_system_test_case"

module Admin
  # Guards the sticky column headers on admin index tables (.table-sticky-head).
  #
  # This is a pure-CSS behaviour with one very easy way to break it: `position:
  # sticky` resolves against the nearest ancestor whose overflow is not
  # `visible`, and an `overflow-x-auto` wrapper (the usual way to let a wide
  # table scroll sideways) becomes exactly that on BOTH axes. With no height it
  # can never scroll vertically, so the header silently stops sticking while the
  # markup still looks correct. Reading the classes doesn't catch it; measuring
  # the rendered box does.
  #
  # Both tests clone the rendered rows before scrolling so the table is
  # guaranteed taller than its scrollport regardless of how many fixtures
  # exist — the DOM ends up identical to what a long list produces, which is all
  # the CSS reacts to.
  class StickyTableHeadersTest < ApplicationSystemTestCase
    include ReimbursementsTestHelpers

    GROW_ROWS = <<~JS.freeze
      const table = document.querySelector(arguments[0]);
      table.querySelectorAll('tbody').forEach((tbody) => {
        const rows = Array.from(tbody.rows);
        for (let i = 0; i < 8; i++) rows.forEach((r) => tbody.appendChild(r.cloneNode(true)));
      });
    JS

    # Scrolls the scrollport until the table's top is well above it, then reports
    # where the header cell ended up relative to the scrollport's top edge.
    # Wrapped in an arrow IIFE because `evaluate_script` injects the script into
    # a `return (…)`, which only accepts a single expression; an arrow keeps
    # `arguments` bound to the injected function so the selectors still arrive.
    MEASURE = <<~JS.freeze
      (() => {
        const table = document.querySelector(arguments[0]);
        const port = document.querySelector(arguments[1]);
        const th = table.querySelector('thead th');
        port.scrollTop = Math.min(
          port.scrollHeight - port.clientHeight,
          (table.getBoundingClientRect().top - port.getBoundingClientRect().top) + port.scrollTop + 200
        );
        return {
          position: getComputedStyle(th).position,
          background: getComputedStyle(th).backgroundColor,
          scrollableY: port.scrollHeight - port.clientHeight,
          tableTop: table.getBoundingClientRect().top,
          portTop: port.getBoundingClientRect().top,
          thTop: th.getBoundingClientRect().top,
        };
      })()
    JS

    def measure(table_selector, port_selector)
      execute_script(GROW_ROWS, table_selector)
      evaluate_script(MEASURE, table_selector, port_selector)
    end

    def assert_header_pinned(result, context)
      assert_equal "sticky", result["position"], "#{context}: header cell is not position:sticky"
      refute_equal "rgba(0, 0, 0, 0)", result["background"],
                   "#{context}: header cell is transparent, so rows show through as they scroll under it"
      assert_operator result["scrollableY"], :>, 0,
                      "#{context}: the header's scrollport cannot scroll vertically, so `sticky` can never engage " \
                      "(usually an unbounded overflow-x wrapper between the table and <main>)"
      assert_operator result["tableTop"], :<, result["portTop"],
                      "#{context}: the table never scrolled past the top of its scrollport, so nothing was proven"
      assert_in_delta result["portTop"], result["thTop"], 2,
                      "#{context}: header should stay pinned to the top of its scrollport"
    end

    # The shared partial behind ~35 admin indexes (and the reimbursements
    # expenses/budgets/actuals lists). These sit straight in <main>, which the
    # admin layout makes the page's scroll container.
    test "shared index table keeps its column headers pinned to the top of <main>" do
      login_as users(:admin)
      visit admin_users_url

      assert_selector "table.table-sticky-head thead th"
      assert_header_pinned measure("table.table-sticky-head", "main"), "shared index table"
    end

    # The hand-written finance tables keep their own horizontal scrollbar, so
    # .table-scroll — not <main> — is the scrollport, and it only works because
    # that class caps its height.
    test "finance table in a horizontal scroll box keeps its headers pinned to the box" do
      grant_finance_permission(users(:member))
      create_reimbursements_budget(name: "Props", nominal_code: "4000")
      login_as users(:member)
      visit overview_admin_reimbursements_budgets_url

      assert_selector ".table-scroll table.table-sticky-head thead th"
      assert_header_pinned measure(".table-scroll table.table-sticky-head", ".table-scroll"),
                           "finance table in .table-scroll"
    end
  end
end
