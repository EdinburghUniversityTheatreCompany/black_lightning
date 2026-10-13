require "test_helper"

class OpportunitiesHomeWidgetCacheTest < ActionController::TestCase
  tests StaticController

  setup do
    ActionController::Base.perform_caching = true
    Rails.cache.clear
  end

  teardown do
    ActionController::Base.perform_caching = false
    Rails.cache.clear
  end

  test "home page shows a renamed department, not the cached name" do
    get :home
    assert_includes response.body, departments(:stage_management).name

    travel 1.minute do
      departments(:stage_management).update!(name: "Stage Wrangling")
      get :home
    end

    assert_includes response.body, "Stage Wrangling"
  end
end
