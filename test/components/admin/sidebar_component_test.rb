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
end
