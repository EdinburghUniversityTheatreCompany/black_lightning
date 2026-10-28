require "application_system_test_case"

module Admin
  # Sticky headers on admin tables. `position: sticky` resolves against the nearest non-`visible`
  # overflow ancestor, and an `overflow-x-auto` wrapper is that on both axes, so with no height the
  # header silently stops sticking. Admin tables therefore sit straight in <main>, the page's
  # scroll container. Only measuring catches it. The rows are cloned first so the table is always
  # taller than the screen.
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

    # Every box between the table and <main> that scrolls vertically: a scrollbar inside the
    # scrolling page.
    INNER_SCROLLERS = <<~JS.freeze
      (() => {
        const found = [];
        for (let el = document.querySelector(arguments[0]).parentElement; el.tagName !== "MAIN"; el = el.parentElement) {
          if (/auto|scroll/.test(getComputedStyle(el).overflowY) && el.scrollHeight > el.clientHeight + 1) {
            found.push(el.className);
          }
        }
        return found;
      })()
    JS

    # How far the rows' last cells (Edit) reach past <main>'s visible right edge, scrolled fully
    # left and fully right (> 0 is off screen).
    EDIT_OVERHANG = <<~JS.freeze
      (() => {
        const main = document.querySelector("main");
        const table = document.querySelector(arguments[0]);
        const overhang = () => {
          const visibleRight = main.getBoundingClientRect().left + main.clientWidth;
          return Math.max(...[...table.querySelectorAll("tbody td:last-child")]
            .map((td) => td.getBoundingClientRect().right - visibleRight));
        };
        main.scrollLeft = 0;
        const atLeft = overhang();
        main.scrollLeft = main.scrollWidth;
        return { tableWidth: table.scrollWidth, mainWidth: main.clientWidth, atLeft, atRight: overhang() };
      })()
    JS

    # Where the permission grid's Update button sits against <main>'s visible box, scrolled fully
    # left and fully right, at whatever vertical position the page is at.
    UPDATE_BUTTON = <<~JS.freeze
      (() => {
        const main = document.querySelector("main");
        const button = document.querySelector("form input[type=submit][value=Update]");
        const port = main.getBoundingClientRect();
        const rect = (left) => {
          main.scrollLeft = left;
          const r = button.getBoundingClientRect();
          return { left: r.left, right: r.right, top: r.top, bottom: r.bottom };
        };
        return {
          screen: { left: port.left, right: port.left + main.clientWidth, top: port.top, bottom: port.top + main.clientHeight },
          sideways: main.scrollWidth - main.clientWidth,
          formBottom: button.closest("form").getBoundingClientRect().bottom,
          atLeft: rect(0), atRight: rect(main.scrollWidth),
        };
      })()
    JS

    # Read off computed styles, so it needs no data tall enough to scroll: every height-capped
    # box in <main> holding a table, and every sticky-header table inside a box that scrolls
    # (where the header can never stick).
    SCROLL_TRAPS = <<~JS.freeze
      (() => {
        const main = document.querySelector("main");
        const scrolls = (el) => { const s = getComputedStyle(el); return /auto|scroll|hidden/.test(s.overflowX + s.overflowY) };
        const capped = [...main.querySelectorAll("*")].filter((el) => el.querySelector("table") &&
          /auto|scroll/.test(getComputedStyle(el).overflowY) && getComputedStyle(el).maxHeight !== "none");
        const trapped = [...main.querySelectorAll("table")].filter((table) => {
          const th = table.querySelector("thead th");
          if (!th || getComputedStyle(th).position !== "sticky") return false;
          for (let el = table.parentElement; el !== main; el = el.parentElement) if (scrolls(el)) return true;
          return false;
        });
        return { tables: main.querySelectorAll("table").length,
                 capped: capped.map((el) => el.className), trapped: trapped.map((el) => el.className) };
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

    def assert_scrolls_with_page(table_selector, context)
      result = measure(table_selector, "main")
      assert_empty evaluate_script(INNER_SCROLLERS, table_selector),
                   "#{context}: the table scrolls vertically in a box of its own, inside the scrolling page"
      assert_header_pinned result, context
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

    # Too wide a table scrolls <main> sideways, with Edit pinned to its right edge.
    test "budgets index scrolls with the page, headers pinned to <main> and Edit on screen" do
      grant_finance_permission(users(:member))
      area = create_reimbursements_area(name: "Medea")
      # Taller, once grown, than the old box's cap of a screen less 12rem.
      5.times { |n| create_reimbursements_budget(name: "Line #{n}", area: area) }
      login_as users(:member)
      visit admin_reimbursements_budgets_url

      assert_selector "table.table-sticky-head thead th"
      assert_scrolls_with_page "table.table-sticky-head", "budgets index"

      resize_window_to(1100, 900)
      width = evaluate_script(EDIT_OVERHANG, "table.table-sticky-head")
      assert_operator width["tableWidth"], :>, width["mainWidth"], "precondition: the table is wider than the page"
      assert_operator width["atLeft"], :<=, 1, "an Edit button is off screen before scrolling sideways: #{width}"
      assert_operator width["atRight"], :<=, 1, "an Edit button is off screen after scrolling sideways: #{width}"
    ensure
      restore_window_size
    end

    test "budgets overview tables scroll with the page, headers pinned to <main>" do
      grant_finance_permission(users(:member))
      create_reimbursements_budget(name: "Props", nominal_code: "4000")
      login_as users(:member)
      visit overview_admin_reimbursements_budgets_url

      assert_selector "table.table-sticky-head thead th"
      assert_scrolls_with_page "table.table-sticky-head", "budgets overview"
    end

    # Every page that once held its tables in a box of its own, seeded so the tables render.
    test "no admin table scrolls in a box of its own" do
      area = create_reimbursements_area(name: "Medea")
      budget = create_reimbursements_budget(name: "Props", area: area)
      batch = create_reimbursements_batch(name: "May")
      create_reimbursements_expense(budget: budget, batch: batch)
      update = ::Reimbursements::BudgetUpdate.create!(effective_date: Date.current)
      update.forecasts.create!(budget: budget, amount: BigDecimal("450"), date: Date.current, reason: "More flyers")
      create_reimbursements_eusa_actual(debit: BigDecimal("20")) # attributed to no budget
      grant_finance_permission(users(:admin))
      login_as users(:admin)

      # Path => the tables it must render, or the page proves nothing.
      {
        admin_reimbursements_budgets_path => 1, overview_admin_reimbursements_budgets_path => 3,
        admin_reimbursements_budget_updates_path => 1, admin_reimbursements_budget_update_path(update.record_id) => 1,
        admin_reimbursements_batch_path(batch.record_id) => 1, admin_reimbursements_area_path(area.record_id) => 2,
        admin_reimbursements_export_path => 1, admin_reimbursements_status_path => 0,
        admin_reimbursements_my_budgets_path => 0, admin_climate_sensors_path => 0,
        debt_overview_admin_events_path => 0, admin_permissions_path => 1,
        permissions_admin_role_path(roles(:committee)) => 1
      }.each do |path, tables|
        visit path
        assert_selector "main"
        found = evaluate_script(SCROLL_TRAPS)
        assert_operator found["tables"], :>=, tables, "#{path}: precondition, its tables render"
        assert_empty found["capped"], "#{path}: a table scrolls vertically in a box of its own"
        assert_empty found["trapped"], "#{path}: a sticky header sits in a box that scrolls, so it never sticks"
      end
    end

    # The grid scrolls with the page both ways, so its Update bar sticks to the screen's bottom
    # and the button to its left edge.
    test "permission grid scrolls with the page and keeps Update on screen" do
      login_as users(:admin)
      resize_window_to(1100, 900)
      visit admin_permissions_url

      assert_selector "form table thead th"
      assert_scrolls_with_page "form table", "permission grid"

      button = evaluate_script(UPDATE_BUTTON)
      screen = button["screen"]
      assert_operator button["sideways"], :>, 0, "precondition: the grid is wider than the page"
      assert_operator button["formBottom"], :>, screen["bottom"], "precondition: the grid runs below the screen"
      %w[atLeft atRight].each do |at|
        rect = button[at]
        assert_operator rect["left"], :>=, screen["left"] - 1, "Update is off the left of the screen (#{at}): #{button}"
        assert_operator rect["right"], :<=, screen["right"] + 1, "Update is off the right of the screen (#{at}): #{button}"
        assert_operator rect["bottom"], :<=, screen["bottom"] + 1, "Update is below the screen (#{at}): #{button}"
        assert_operator rect["top"], :>=, screen["top"] - 1, "Update is above the screen (#{at}): #{button}"
      end
    ensure
      restore_window_size
    end
  end
end
