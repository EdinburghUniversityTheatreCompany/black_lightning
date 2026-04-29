require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  def current_ability
    @current_user.ability
  end

  test "current environment should return admin for admin pages" do
    @current_user = users(:admin)

    assert_equal "admin", current_environment("admin")
    assert_equal "admin", current_environment("administrator")
    assert_equal "admin", current_environment("/admin/shows/the-wondrous-adventures")

    assert_equal "application", current_environment("pineapple")
  end

  test "current environment should return application in every case if the user does not have backend access" do
    @current_user = users(:user)

    assert_equal "application", current_environment("admin")
    assert_equal "application", current_environment("administrator")
    assert_equal "application", current_environment("/admin/shows/the-wondrous-adventures")
    assert_equal "application", current_environment("pineapple")
  end
  test "merge hash" do
    a = {
      ingredients: [ :pineapple ],
      jobs: [ :chef ]
    }

    b = {
      ingredients: [ :cheese, :pineapple ],
      jobs: [ :techie ],
      lead: "Finbar the Viking"
    }

    result = {
      ingredients: [ :pineapple, :cheese ],
      jobs: [ :chef, :techie ],
      lead: "Finbar the Viking"
    }

    assert_equal result, merge_hash(a, b)
  end

  test "Get spark_seat_widget" do
    slug = "hexagon-finbar-pineapple-red"
    assert_match slug, spark_seat_widget(slug)
  end

  test "active_storage_proxy_url returns a blob proxy URL for an attachment" do
    user = FactoryBot.create(:user)
    user.avatar.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png", content_type: "image/png")

    url = active_storage_proxy_url(user.avatar)

    assert_match %r{/rails/active_storage/blobs/proxy/}, url
    assert_no_match %r{X-Amz}, url
  end

  test "active_storage_proxy_url returns a representation proxy URL for a variant" do
    user = FactoryBot.create(:user)
    user.avatar.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png", content_type: "image/png")

    variant = user.avatar.variant(resize_to_limit: [ 100, 100 ])
    url = active_storage_proxy_url(variant)

    assert_match %r{/rails/active_storage/representations/proxy/}, url
    assert_no_match %r{X-Amz}, url
  end

  # We now use the built-in function, but it is still good to test it
  test "Get strip_tags" do
    assert_equal "This is stripped", strip_tags("<!-- it happened 2 years before 1980, idk when exactly -->This is stripped")
    assert_equal "This is stripped", strip_tags('<div><span title="hello world!">This is stripped</div>')
  end
end
