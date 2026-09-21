class Admin::SidebarComponent < ViewComponent::Base
  # The selectors a finance screen keeps in the URL. A sidebar link that drops
  # them silently reverts the operator to the active year and every cost
  # centre, which on a two-pot portal means the next screen is about money
  # they were not looking at — the one place the "URL as state" rule was
  # broken, because the sidebar is rendered once for every page and knew
  # nothing about them.
  #
  # Carried on FINANCE items only (the ones marked `scoped: true`): every
  # finance controller resolves both through FinanceController, so a screen
  # that does not display a selector still scopes its store by them, while a
  # producer's own claims are deliberately never year- or centre-scoped.
  SCOPE_PARAMS = %w[year cost_centre].freeze

  # Other spellings of the same coordinate. An item pointing at a specific pot
  # with ?cost_centre_id= is stating a scope of its own, and the key wins over
  # the id in FinanceController#resolve_cost_centre! — so appending the carried
  # key beside it would silently override the link's own choice.
  SCOPE_ALIASES = { "cost_centre" => %w[cost_centre cost_centre_id], "year" => %w[year] }.freeze

  def initialize(nav_items:, current_user:, current_path:, scope_params: {})
    @nav_items = nav_items
    @current_user = current_user
    @current_path = current_path
    @scope_params = scope_params.to_h.slice(*SCOPE_PARAMS).compact_blank
  end

  private

  # An item's href with the current year and cost centre appended, for the
  # items that asked for them. An item that already carries a query string
  # keeps it and wins on a clash: it is stating a scope of its own.
  def item_href(item)
    path = item[:path].to_s
    return path unless item[:scoped] && @scope_params.any?

    base, _, existing = path.partition("?")
    # PARSED, never matched as a substring: "financial_year=" contains "year="
    # and "cost_centre_id=" contains neither "cost_centre=" nor the whole of
    # it, so either direction of substring test gets one of them wrong.
    claimed = Rack::Utils.parse_nested_query(existing).keys
    carried = @scope_params.reject do |key, _|
      SCOPE_ALIASES.fetch(key, [ key ]).any? { |spelling| claimed.include?(spelling) }
    end
    return path if carried.empty?

    query = [ existing.presence, carried.to_query ].compact.join("&")
    "#{base}?#{query}"
  end

  # Pages that belong to a category but sit under no item's path: the two
  # import wizards and the workbook download all live at the reimbursements
  # root, so the whole Finance menu used to collapse the moment an operator
  # entered one — losing their bearings exactly where the flow is longest.
  ORPHAN_PAGES = {
    "Finance" => %w[
      /admin/reimbursements/budget_import
      /admin/reimbursements/expense_import
      /admin/reimbursements/export
    ]
  }.freeze

  def category_open?(category)
    return true if orphan_page?(category)

    category[:children]&.any? { |item| active_item?(item) }
  end

  def orphan_page?(category)
    current = normalise_path(@current_path)
    ORPHAN_PAGES.fetch(category[:title], []).any? do |path|
      current == path || current.start_with?("#{path}/")
    end
  end

  # A nav item lights up for its own page and anything beneath it. Two things
  # the bare `start_with?` this replaced got wrong:
  #
  # - It compared against `request.fullpath`, which carries the query string.
  #   This app deliberately keeps filter state in the URL, so an equality check
  #   could never match ("/admin/shows" != "/admin/shows?q[name]=x").
  # - It matched on characters rather than path segments, so an item at
  #   "/admin/staffings" would light up for "/admin/staffings_archive".
  #
  # `exact: true` narrows the match to the page itself, for an item whose path
  # is a prefix of a sibling's -- without it a parent lights up whenever one of
  # its children is open.
  def active_item?(item)
    path = normalise_path(item[:path])
    return false if path.empty?

    current = normalise_path(@current_path)
    return current == path if item[:exact]

    current == path || current.start_with?("#{path}/")
  end

  def normalise_path(path)
    path.to_s.split("?").first.to_s.chomp("/")
  end

  def user_display_name
    @current_user.first_name.presence || @current_user.email
  end
end
