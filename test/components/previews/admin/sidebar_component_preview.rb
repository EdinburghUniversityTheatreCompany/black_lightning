class Admin::SidebarComponentPreview < Admin::ApplicationComponentPreview
  def default
    nav_items = [
      { title: "Productions", fa_icon: "fa-industry", children: [
        { title: "Shows", path: "/admin/shows", fa_icon: "fa-masks-theater" },
        { title: "Events", path: "/admin/events", fa_icon: "fa-calendar" }
      ] },
      { title: "Users", fa_icon: "fa-circle-user", children: [
        { title: "Users", path: "/admin/users", fa_icon: "fa-circle-user" }
      ] }
    ]
    render Admin::SidebarComponent.new(
      nav_items: nav_items,
      current_user: sample_user,
      current_path: "/admin/shows"
    )
  end
end
