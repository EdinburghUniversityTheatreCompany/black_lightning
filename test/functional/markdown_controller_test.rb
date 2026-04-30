require "test_helper"

class MarkdownControllerTest < ActionController::TestCase
  test "should generate preview" do
    markdown = File.read(Rails.root.join("test/markdown.md"))
    html = File.read(Rails.root.join("test/markdown.html"))

    assert_not_nil markdown

    post :preview, body: { input_html: CGI.escape(markdown) }.to_json
    assert_response :success

    response_html = ActiveSupport::JSON.decode(response.body)["rendered_md"]

    assert_equal response_html.strip, html.strip
  end

  test "upload creates attachment and returns url for valid image" do
    sign_in users(:admin)
    image = fixture_file_upload("test_image.png", "image/png")
    post :upload, params: { image: image }
    assert_response :success
    json = JSON.parse(response.body)
    assert json["url"].present?
    assert json["alt"].present?
    assert Attachment.where("name LIKE 'md-upload-%'").exists?
  end

  test "upload associates item when item_type and item_id provided" do
    sign_in users(:admin)
    news_item = news(:current_news)
    image = fixture_file_upload("test_image.png", "image/png")
    post :upload, params: { image: image, item_type: "News", item_id: news_item.id }
    assert_response :success
    attachment = Attachment.last
    assert_equal news_item, attachment.item
  end

  test "upload rejects non-image content type" do
    sign_in users(:admin)
    image = fixture_file_upload("test_image.png", "application/pdf")
    post :upload, params: { image: image }
    assert_response :unprocessable_entity
  end
end
