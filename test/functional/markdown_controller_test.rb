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
    assert_predicate Attachment.find_by(name: json["alt"]), :present?
  end

  test "upload associates item when item_type and item_id provided" do
    sign_in users(:admin)
    news_item = news(:current_news)
    image = fixture_file_upload("test_image.png", "image/png")
    post :upload, params: { image: image, item_type: "News", item_id: news_item.id }
    assert_response :success
    # The record THIS request created, found by the unique name the response
    # hands back. Attachment carries `default_scope { order("name ASC") }`, so
    # `Attachment.last` is the alphabetically last row in the table -- not the
    # newest -- and any row sorting after "md-upload-..." silently stands in
    # for the one under test. Harmless against a schema-loaded worker database,
    # wrong against a seeded one.
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
