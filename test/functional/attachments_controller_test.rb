require "test_helper"

class AttachmentsControllerTest < ActionController::TestCase
  FIRST_CHUNK = "the first chunk of the file".freeze

  # The Accept header Chrome sends for an <img>, which is what most of these attachments are.
  IMAGE_ACCEPT_HEADER = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8".freeze

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

  test "pdf files serve with inline disposition" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)

    get :file, params: { slug: attachment.name }

    assert_response :success
    assert_equal "inline; test.pdf", response.headers["Content-Disposition"]
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
  end

  test "images serve with inline disposition" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)
    attachment.file.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png", content_type: "image/png")

    get :file, params: { slug: attachment.name }

    assert_response :success
    assert_equal "inline; test.png", response.headers["Content-Disposition"]
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
  end

  test "office documents serve with attachment disposition" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)
    attachment.file.attach(io: StringIO.new("fake docx"), filename: "document.docx", content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")

    get :file, params: { slug: attachment.name }

    assert_response :success
    assert_equal "attachment; document.docx", response.headers["Content-Disposition"]
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
  end

  test "text files serve with attachment disposition" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)
    attachment.file.attach(io: StringIO.new("hello world"), filename: "document.txt", content_type: "text/plain")

    get :file, params: { slug: attachment.name }

    assert_response :success
    assert_equal "attachment; document.txt", response.headers["Content-Disposition"]
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
  end

  test "renders the 404 page when the attachment has no file" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)
    attachment.file.purge

    get :file, params: { slug: attachment.name }

    assert_response :not_found
    assert_match "There is no file attached.", response.body
  end

  # The response has already been given the file's Content-Type (and the headers that go with
  # serving a file) by the time the download fails, so rendering the error page into it used to
  # raise RespondToMismatchError on top of the original error.
  test "renders the 404 page when the file is missing from storage" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)
    attachment.file.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png", content_type: "image/png")
    ActiveStorage::Blob.service.delete(attachment.file.key)

    @request.headers["Accept"] = IMAGE_ACCEPT_HEADER

    get :file, params: { slug: attachment.name }

    assert_response :not_found
    assert_equal "text/html", response.media_type
    assert_nil response.headers["Content-Disposition"]
    assert_nil response.headers["Content-Security-Policy"], "The sandbox CSP would have stripped the error page of its styling"
  end

  test "discards the bytes already streamed when the download fails part-way through" do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)

    with_truncated_download(attachment.file.blob.service) do
      get :file, params: { slug: attachment.name }
    end

    assert_response :not_found
    assert_no_match FIRST_CHUNK, response.body, "The half-served file was left on the response under the error page"
  end

  private

  # Makes the storage service fail part-way through a streamed download for the duration of the
  # block, the way S3 does when the connection drops between two of the ranged GETs it reads a
  # blob with.
  def with_truncated_download(service)
    service.define_singleton_method(:download) do |key, &block|
      next super(key, &block) if block.nil?

      block.call(FIRST_CHUNK)
      raise ActiveStorage::FileNotFoundError
    end

    yield
  ensure
    service.singleton_class.remove_method(:download)
  end
end
