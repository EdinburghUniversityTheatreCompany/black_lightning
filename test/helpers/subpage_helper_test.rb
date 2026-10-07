require "test_helper"

class SubpageHelperTest < ActionView::TestCase
  test "get subpage root page" do
    assert_equal "about", get_subpage_root_url("about", "overview")
    assert_equal "about", get_subpage_root_url("about", nil)
    assert_equal "about", get_subpage_root_url("about", "")
    assert_equal "about", get_subpage_root_url("about/", "/")
    assert_equal "about/secretary", get_subpage_root_url("about", "secretary")
    assert_equal "about/secretary", get_subpage_root_url("about", "secretary/")
    assert_equal "about/secretary", get_subpage_root_url("about", "/secretary/")
    assert_equal "about/secretary/minutes", get_subpage_root_url("about", "secretary/minutes")
    assert_equal "about/secretary/minutes", get_subpage_root_url("about", "secretary/minutes/")
    assert_equal "about/pineapple/hexagon/viking", get_subpage_root_url("about", "pineapple/hexagon/viking")
  end
end
