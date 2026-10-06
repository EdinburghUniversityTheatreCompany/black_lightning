class Admin::SidebarComponent < ViewComponent::Base
  # The selectors a finance screen keeps in the URL. A sidebar link that drops them
  # silently reverts the operator to the active year and every cost centre.
  # Carried on finance items only (`scoped: true`): every finance controller scopes
  # its store by them, even where it shows no selector. A producer's own claims are
  # deliberately never year- or centre-scoped.
  SCOPE_PARAMS = %w[year cost_centre].freeze

  # Other spellings of the same coordinate. The key beats ?cost_centre_id= in
  # FinanceController#resolve_cost_centre!, so appending it beside an item's own
  # cost_centre_id would override that item's choice.
  SCOPE_ALIASES = { "cost_centre" => %w[cost_centre cost_centre_id], "year" => %w[year] }.freeze

  def initialize(nav_items:, current_user:, current_path:, scope_params: {})
    @nav_items = nav_items
    @current_user = current_user
    @current_path = current_path
    @scope_params = scope_params.to_h.slice(*SCOPE_PARAMS).compact_blank
  end

  private

  # An item's href with the current year and cost centre appended, for scoped items.
  # A scope the item already carries in its own query string wins on a clash.
  def item_href(item)
    path = item[:path].to_s
    return path unless item[:scoped] && @scope_params.any?

    base, _, existing = path.partition("?")
    # Parsed, never matched as a substring: "financial_year=" contains "year=",
    # and "cost_centre_id=" is a different spelling of cost_centre.
    claimed = Rack::Utils.parse_nested_query(existing).keys
    carried = @scope_params.reject do |key, _|
      SCOPE_ALIASES.fetch(key, [ key ]).any? { |spelling| claimed.include?(spelling) }
    end
    return path if carried.empty?

    query = [ existing.presence, carried.to_query ].compact.join("&")
    "#{base}?#{query}"
  end

  # Pages that belong to a category but sit under no item's path. Without this
  # the Finance menu collapses inside the two import wizards.
  ORPHAN_PAGES = {
    "Finance" => %w[
      /admin/reimbursements/budget_import
      /admin/reimbursements/expense_import
    ]
  }.freeze

  def category_open?(category)
    return true if orphan_page?(category)

    category[:children].any? { |item| active_item?(item) }
  end

  def orphan_page?(category)
    current = normalise_path(@current_path)
    ORPHAN_PAGES.fetch(category[:title], []).any? do |path|
      current == path || current.start_with?("#{path}/")
    end
  end

  # An item lights up for its own page and anything beneath it. The query string is
  # stripped because current_path is request.fullpath and filter state lives in the
  # URL. Matches path segments, not characters: "/admin/staffings" must not light up
  # for "/admin/staffings_archive". `exact: true` matches the page alone, for an item
  # whose path prefixes a sibling's.
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
