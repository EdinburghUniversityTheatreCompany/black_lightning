require 'test_helper'

class MarkdownControllerTest < ActionController::TestCase
  test "should generate preview" do
    markdown = File.read(Rails.root.join("test/kramdown.md"))
    html = File.read(Rails.root.join("test/kramdown.html"))

    raw_post :preview, {}, { input_html: markdown }.to_json
    assert_response :success

    response_html = ActiveSupport::JSON.decode(response.body)['rendered_md']

    assert_equal response_html, html
  end
end
