require "test_helper"
require "application_integration_test"

class Admin::VersionHistoriesControllerTest < ApplicationIntegrationTest
  setup do
    @editable_block = admin_editable_blocks(:public)

    # Create versions by updating the editable block with PaperTrail enabled
    PaperTrail.request(enabled: true) do
      PaperTrail.request.whodunnit = users(:admin).id

      @editable_block.update!(content: "Updated content for version history test")
      @editable_block.update!(content: "Second update with more changes", version_note: "Fixed typos")
    end

    @version_with_note = @editable_block.versions.last

    sign_in users(:admin)
  end

  test "should get index" do
    get admin_editable_block_version_histories_path(@editable_block)

    assert_response :success
    assert_select "table"
    assert_select "td", text: "Update"
  end

  test "index shows version note" do
    get admin_editable_block_version_histories_path(@editable_block)

    assert_response :success
    assert_select "td", text: "Fixed typos"
  end

  test "index shows author name" do
    get admin_editable_block_version_histories_path(@editable_block)

    assert_response :success
    assert_match users(:admin).first_name, response.body
  end

  test "should show diff for update version" do
    version = @editable_block.versions.where(event: "update").first

    get admin_editable_block_version_history_path(@editable_block, version)

    assert_response :success
    assert_select "h6", text: "Content"
  end

  test "show displays version note" do
    get admin_editable_block_version_history_path(@editable_block, @version_with_note)

    assert_response :success
    assert_select "em", text: "Fixed typos"
  end

  test "should store version_note on update" do
    PaperTrail.request(enabled: true) do
      PaperTrail.request.whodunnit = users(:admin).id

      @editable_block.update!(content: "Another update", version_note: "Added new section")
    end

    assert_equal "Added new section", @editable_block.versions.last.version_note
  end

  test "version_note is not stored on create" do
    PaperTrail.request(enabled: true) do
      block = Admin::EditableBlock.create!(name: "Version Test Block", content: "Test content")

      assert_nil block.versions.last.version_note
    end
  end

  test "diff_for_version returns changed attributes" do
    version = @editable_block.versions.where(event: "update").first
    diff = @editable_block.diff_for_version(version)

    assert diff.key?("content"), "Expected diff to contain 'content' key"
    assert_not diff.key?("id"), "Expected diff to not contain 'id' key"
    assert_not diff.key?("updated_at"), "Expected diff to not contain 'updated_at' key"
  end

  test "unauthenticated user cannot view history" do
    sign_out users(:admin)

    get admin_editable_block_version_histories_path(@editable_block)

    assert_response :redirect
  end
end
