require "application_system_test_case"

# Signing out, or in again, in another tab voids the CSRF token of every page already open, so
# its next save fails. The page, and what was typed on it, stays put.
class StalePageTest < ApplicationSystemTestCase
  PASSWORD = "Stale-page-1".freeze

  setup do
    @forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown { ActionController::Base.allow_forgery_protection = @forgery_protection }

  test "a form saved after signing in again elsewhere keeps its text and says nothing was saved" do
    login_as users(:admin)
    visit new_admin_department_path
    fill_in "Name", with: "Puppetry"
    fill_in "Match terms", with: "puppeteer, puppet maker"

    sign_out_and_in_again_in_another_window(users(:admin))
    click_button "Create Department"

    assert_selector ".swal2-container", text: ApplicationController::STALE_PAGE_MESSAGE
    assert_field "Name", with: "Puppetry"
    assert_field "Match terms", with: "puppeteer, puppet maker"
    assert_current_path new_admin_department_path
    assert_not Department.exists?(name: "Puppetry")
  end

  test "an image added after signing in again elsewhere is refused in the same words" do
    login_as users(:member)
    visit new_complaint_path
    assert_selector ".milkdown-editor-wrap .ProseMirror"

    sign_out_and_in_again_in_another_window(users(:member))
    find("[data-controller='markdown-editor'] input[type='file']", visible: :all)
      .set(file_fixture("test_image.png").to_s)

    assert_selector ".swal2-popup", text: "test_image.png: #{ApplicationController::STALE_PAGE_MESSAGE}"
    assert_no_selector ".ProseMirror img"
  end

  private

  # Clearing the cookies signs out every tab, as they share one jar (WebDriver clears only the open
  # site's, hence the first visit). Then it signs in again through the form, as a person would.
  def sign_out_and_in_again_in_another_window(user)
    user.update_column(:encrypted_password, Devise::Encryptor.digest(User, PASSWORD))
    window = open_new_window
    within_window(window) do
      visit new_user_session_path
      page.driver.browser.manage.delete_all_cookies

      visit new_user_session_path
      fill_in "Email", with: user.email
      fill_in "Password", with: PASSWORD
      click_button "Log in"
      assert_no_current_path new_user_session_path
    end
    window.close
  end
end
