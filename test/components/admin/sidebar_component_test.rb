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
end
