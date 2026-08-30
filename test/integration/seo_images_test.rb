require "test_helper"

# 4,943 of 4,948 images on the live site had no alt attribute at all, and the loading strategy was
# exactly inverted: the masthead above the fold inherited the app-wide lazy default while eight
# cards below it loaded eagerly. Measured, that cost 1552ms of homepage LCP on a throttled phone.
class SeoImagesTest < ActionDispatch::IntegrationTest
  setup do
    @show = FactoryBot.create(:show, name: "The Rocky Horror Show", is_public: true)
  end

  test "every image on the homepage has an alt attribute" do
    get root_path

    assert_response :success
    images = css_select("img")
    assert_operator images.length, :>, 0, "no images rendered, so this proves nothing"

    missing = images.reject { |img| img.attributes.key?("alt") }
    assert_empty missing.map { |img| img["src"] }, "images with no alt attribute"
  end

  test "every image on a show page has an alt attribute" do
    get show_path(@show)

    missing = css_select("img").reject { |img| img.attributes.key?("alt") }
    assert_empty missing.map { |img| img["src"] }, "images with no alt attribute"
  end

  test "the masthead is eager and high priority, being the desktop LCP element" do
    get root_path

    masthead = css_select("img[src*='Header']").first
    assert_not_nil masthead, "the masthead did not render"
    assert_equal "eager", masthead["loading"]
    assert_equal "high", masthead["fetchpriority"]
    assert_predicate masthead["alt"].to_s, :present?, "the masthead is inside a link, so it needs a name"
  end

  # The whole point of the inversion: nothing below the fold competes with the LCP image. Two
  # images are above it -- the masthead and the first carousel slide -- and both opt out
  # deliberately. Everything after them waits.
  test "only the two above-the-fold images are eager" do
    get root_path

    loadings = css_select("img").map { |img| img["loading"] }
    eager_positions = loadings.each_index.select { |i| loadings[i] == "eager" }

    assert_operator eager_positions.length, :<=, 2, "#{eager_positions.length} images load eagerly"
    assert_equal eager_positions, (0...eager_positions.length).to_a,
                 "an eager image sits below a lazy one, so the inversion is back"
  end

  test "the show cards below the fold all wait" do
    get root_path

    cards = css_select("img[src*='active_storage']").drop(1)
    assert(cards.all? { |img| img["loading"] == "lazy" }, "a card image is not lazy")
  end

  test "a show banner names the show" do
    get show_path(@show)

    # The masthead is high-priority too, and comes first in the document.
    banner = css_select("img[fetchpriority=high]").reject { |img| img["src"].to_s.include?("Header") }.first
    assert_not_nil banner, "the show banner did not opt out of lazy loading"
    assert_equal "The Rocky Horror Show", banner["alt"]
  end
end
