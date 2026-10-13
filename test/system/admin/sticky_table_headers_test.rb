require "application_system_test_case"

module Admin
  # Sticky headers on admin index tables (.table-sticky-head). `position: sticky` resolves against
  # the nearest non-`visible` overflow ancestor, and an `overflow-x-auto` wrapper is that on both
  # axes, so with no height the header silently stops sticking. Only measuring the box catches it.
  # The rows are cloned first so the table is always taller than its scrollport.
  class StickyTableHeadersTest < ApplicationSystemTestCase
    include ReimbursementsTestHelpers

    GROW_ROWS = <<~JS.freeze
      const table = document.querySelector(arguments[0]);
      table.querySelectorAll('tbody').forEach((tbody) => {
        const rows = Array.from(tbody.rows);
        for (let i = 0; i < 8; i++) rows.forEach((r) => tbody.appendChild(r.cloneNode(true)));
      });
    JS

    # Scrolls the table's top well past the scrollport's and reports where the header cell sits.
    # An arrow IIFE: `evaluate_script` wraps the script in `return (…)`, which takes one
    # expression, and an arrow keeps `arguments` bound so the selectors still arrive.
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
