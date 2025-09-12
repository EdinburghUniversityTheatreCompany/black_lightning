require "test_helper"

class AttachmentsControllerTest < ActionController::TestCase
  setup do
    @editable_block = admin_editable_blocks(:public)
  end

  test "should get file" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)

    get :file, params: { slug: attachment.name }

    assert_response :success

    assert_equal "application/pdf", response.headers["Content-Type"]
    assert_equal "inline; test.pdf", response.headers["Content-Disposition"]
  end

  # Should not return a thumbnail, but just a file link.
  test "should get pdf file as thumb" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)

    get :file, params: { slug: attachment.name, style: "ThUmb" }

    assert_response :success

    assert_equal "application/pdf", response.headers["Content-Type"]
    assert_equal "inline; #{attachment.file.filename}", response.headers["Content-Disposition"]
  end

  test "should get image file as thumb" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)
    attachment.file.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png", content_type: "image/png")

    assert attachment.file.image?

    get :file, params: { slug: attachment.name, style: :thumb }

    assert_response :success

    assert_equal "image/png", response.headers["Content-Type"]
    assert_equal "inline; #{attachment.file.filename}", response.headers["Content-Disposition"]

    # It would be nice to check the dimensions of the response.
  end

  test "should not get file for admin page editable_block when not logged in" do
    admin_editable_block = admin_editable_blocks(:admin)
    attachment = FactoryBot.create(:attachment, item: admin_editable_block, access_level: 2)

    get :file, params: { slug: attachment.name }

    assert_response 403
  end

  test "should get file for admin page editable_block when logged in as admin" do
    sign_in users(:admin)
    admin_editable_block = admin_editable_blocks(:admin)
    attachment = FactoryBot.create(:attachment, item: admin_editable_block)

    get :file, params: { slug: attachment.name }
    assert_response :success
  end

  # The following two tests should be identical apart from if the proposal is approved or not.
  # One should be forbidden, one should be success, as normal users not on proposals can only see
  # attachments after they can see the proposal (so when they are approved and past the editing deadline)
  test "someone not on the proposal should NOT be able to view an attachment on not approved proposal after the editing deadline" do
    sign_in users(:member)

    proposal = FactoryBot.create(:proposal, status: :awaiting_approval, submission_deadline: -1.days.from_now)

    question = FactoryBot.create(:question, questionable: proposal, answered: true, response_type: "File")
    attachment = question.answers.first.attachments.first
    attachment.update(access_level: 1)

    assert_not_nil attachment

    get :file, params: { slug: attachment.name }

    assert_response :forbidden
  end

  test "someone not on the proposal should be able to view an attachment on an approved proposal after the editing deadline" do
    sign_in users(:member)

    proposal = FactoryBot.create(:proposal, status: :approved, submission_deadline: -1.days.from_now)
    proposal.call.update(editing_deadline: proposal.call.submission_deadline.advance(hours: 1))

    question = FactoryBot.create(:question, questionable: proposal, answered: true, response_type: "File")
    attachment = question.answers.first.attachments.first
    attachment.update(access_level: 1)

    assert_not_nil attachment

    assert_equal 1, attachment.access_level, "The attachment does not have attachment level 1, so the user will not be able to see it."

    get :file, params: { slug: attachment.name }

    assert_response :success
  end
end
