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

  test "active_storage_proxy_url gives a stable proxy URL for an attachment and for a variant" do
    user = FactoryBot.create(:user)
    user.avatar.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png", content_type: "image/png")

    blob_url = active_storage_proxy_url(user.avatar)
    variant_url = active_storage_proxy_url(user.avatar.variant(resize_to_limit: [ 100, 100 ]))

    assert_match %r{/rails/active_storage/blobs/proxy/}, blob_url
    assert_match %r{/rails/active_storage/representations/proxy/}, variant_url
    assert_no_match %r{X-Amz}, blob_url
    assert_no_match %r{X-Amz}, variant_url
  end
end
