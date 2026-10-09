require "test_helper"

class MarkdownControllerTest < ActionController::TestCase
  # The upload rate limit counts in Rails.cache.
  setup { Rails.cache.clear }

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
    post :upload, params: { image: png }
    assert_response :success
    json = JSON.parse(response.body)
    assert json["url"].present?
    assert json["alt"].present?
    assert_predicate Attachment.find_by(name: json["alt"]), :present?
  end

  test "upload associates item when item_type and item_id provided" do
    sign_in users(:admin)
    news_item = news(:current_news)
    post :upload, params: { image: png, item_type: "News", item_id: news_item.id }
    assert_response :success
    assert_equal news_item, uploaded_attachment.item
  end

  test "upload rejects non-image content type" do
    sign_in users(:admin)
    image = fixture_file_upload("test_image.png", "application/pdf")
    post :upload, params: { image: image }
    assert_response :unprocessable_entity
  end

  test "upload refuses a visitor who is not signed in" do
    request.accept = "application/json"

    assert_no_difference("Attachment.count") { post :upload, params: { image: png } }
    assert_response :unauthorized
  end

  test "upload refuses to attach to a record the user cannot edit" do
    sign_in users(:member)

    assert_no_difference("Attachment.count") do
      post :upload, params: { image: png, item_type: "News", item_id: news(:current_news).id }
    end
    assert_response :forbidden
  end

  test "upload refuses a type no markdown editor is on, even for an admin" do
    sign_in users(:admin)

    assert_no_difference("Attachment.count") do
      post :upload, params: { image: png, item_type: "Role", item_id: roles(:member).id }
    end
    assert_response :unprocessable_entity
  end

  test "upload attaches to a record the user may edit" do
    member = users(:member)
    sign_in member

    post :upload, params: { image: png, item_type: "User", item_id: member.id }

    assert_response :success
    assert_equal member, uploaded_attachment.item
  end

  test "upload attaches to an answer on a questionnaire the user answers" do
    questionnaire = FactoryBot.create(:questionnaire, :with_team_members)
    answer = FactoryBot.create(:answer, question: questionnaire.questions.first, answerable: questionnaire)
    sign_in questionnaire.users.first

    post :upload, params: { image: png, item_type: "Admin::Answer", item_id: answer.id }

    assert_response :success
    assert_equal answer, uploaded_attachment.item
  end

  test "upload attaches to a category on the user's own marketing creatives profile" do
    member = users(:member)
    profile = FactoryBot.create(:marketing_creatives_profile, attach_user: false, user: member)
    category_info = profile.category_infos.first
    sign_in member

    post :upload, params: { image: png, item_type: "MarketingCreatives::CategoryInfo", item_id: category_info.id }

    assert_response :success
    assert_equal category_info, uploaded_attachment.item
  end

  test "every item type names a model" do
    MarkdownController::ITEM_TYPES.each do |type|
      assert_operator type.safe_constantize, :<, ApplicationRecord, "#{type} is not a model"
    end
  end

  test "preview and upload work for a user still completing their profile, whose page has the editor" do
    member = users(:member)
    member.update_columns(profile_completed_at: nil)
    sign_in member

    post :preview, params: { input_html: "**bio**" }, as: :json
    assert_response :success

    post :upload, params: { image: png, item_type: "User", item_id: member.id }
    assert_response :success
  end

  test "upload answers 429 after 30 requests in a minute" do
    sign_in users(:member)

    30.times { post :upload }
    assert_response :unprocessable_entity

    assert_no_difference("Attachment.count") { post :upload, params: { image: png } }
    assert_response :too_many_requests
  end

  private

  def png = fixture_file_upload("test_image.png", "image/png")

  # Attachment's default_scope orders by name, so Attachment.last is not the newest row.
  def uploaded_attachment = Attachment.find_by!(name: JSON.parse(response.body)["alt"])
end
