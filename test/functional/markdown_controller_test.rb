require "test_helper"

class MarkdownControllerTest < ActionController::TestCase
  test "should generate preview" do
    markdown = File.read(Rails.root.join("test/markdown.md"))
    html = File.read(Rails.root.join("test/markdown.html"))

    assert_not_nil markdown

    post :preview, params: { input_html: markdown }, as: :json
    assert_response :success

    response_html = ActiveSupport::JSON.decode(response.body)["rendered_md"]

    assert_equal response_html.strip, html.strip
  end

  test "preview renders the text as typed, with no URL decoding" do
    post :preview, params: { input_html: "+ one\n+ two\n\n1+1 is 100%20" }, as: :json

    html = JSON.parse(response.body)["rendered_md"]

    assert_equal 2, Nokogiri::HTML5.fragment(html).css("li").size
    assert_includes html, "1+1 is 100%20"
  end

  test "upload creates attachment and returns url for valid image" do
    sign_in users(:admin)
    image = fixture_file_upload("test_image.png", "image/png")
    post :upload, params: { image: image }
    assert_response :success
    json = JSON.parse(response.body)
    assert json["url"].present?
    assert json["alt"].present?
    assert_predicate Attachment.find_by(name: json["alt"]), :present?
  end

  test "upload associates item when item_type and item_id provided" do
    sign_in users(:admin)
    news_item = news(:current_news)
    image = fixture_file_upload("test_image.png", "image/png")
    post :upload, params: { image: image, item_type: "News", item_id: news_item.id }
    assert_response :success
    # Attachment's default_scope orders by name, so Attachment.last is not the newest row.
    attachment = Attachment.find_by!(name: JSON.parse(response.body)["alt"])
    assert_equal news_item, attachment.item
  end

  test "upload rejects non-image content type" do
    sign_in users(:admin)
    image = fixture_file_upload("test_image.png", "application/pdf")
    post :upload, params: { image: image }
    assert_response :unprocessable_entity
  end
end
