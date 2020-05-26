require 'test_helper'

class Admin::MembershipControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end
  test 'returns nothing for empty search' do
    get :check_membership, params: { search: nil }
    assert_response :not_found

    get :check_membership, params: { search: '' }
    assert_response :not_found

    get :check_membership, params: { search: '  ' }
    assert_response :not_found
  end

  test 'search for an user name' do
    user = FactoryBot.create(:user, first_name: 'Dennis', last_name: 'Donkey')

    not_found_response = '{"response":"Dennis Donkey is not a current member"}'

    get :check_membership, params: { search: user.first_name }
    assert_equal not_found_response, response.body

    get :check_membership, params: { search: user.last_name }
    assert_equal not_found_response, response.body

    user.add_role :member

    get :check_membership, params: { search: user.first_name.last + ' ' + user.last_name.first }
    assert_equal '{"response":"Dennis Donkey is a current member","image":"/avatars/original/missing.png"}', response.body
  end

  test 'search for invalid user' do
    get :check_membership, params: { search: 'pineapple is not a name for a human' }
    assert_response :not_found
  end
end
