class Admin::SidebarComponent < ViewComponent::Base
  def initialize(nav_items:, current_user:, current_path:)
    @nav_items = nav_items
    @current_user = current_user
    @current_path = current_path
  end

  private

  def category_open?(category)
    category[:children]&.any? { |item| active_item?(item) }
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
