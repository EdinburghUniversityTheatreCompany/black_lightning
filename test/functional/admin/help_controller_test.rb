require 'test_helper'

class Admin::HelpControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should get kramdown' do
    get :kramdown
    assert_response :success
  end

  test 'should get kramdown as text' do
    get :kramdown, format: :text

    assert_response :success
  end

  test 'should get venue location' do
    get :venue_location
  end
end
