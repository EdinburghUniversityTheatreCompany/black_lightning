require 'test_helper'

class Admin::ComplaintsControllerTest < ActionController::TestCase
  setup do
    admin = users(:admin)
    admin.add_role('Welfare Contact')

    sign_in admin

    @complaint = FactoryBot.create(:complaint)
  end

  test 'should get index' do
    FactoryBot.create_list(:complaint, 10)

    get :index
    assert_response :success
  end

  test 'should get show' do
    get :show, params: { id: @complaint }
    assert_response :success
  end

  test 'should get edit' do
    get :edit, params: { id: @complaint }

    assert_response :success
  end

  test 'should update complaint' do
    attrs = FactoryBot.attributes_for(:complaint)

    put :update, params: { id: @complaint, complaint: attrs }

    assert_redirected_to admin_complaint_path(assigns(:complaint))

    # Make sure only allowed things change.
    assert_equal @complaint.subject, assigns(:complaint).subject
    assert_equal @complaint.description, assigns(:complaint).description
    assert_equal attrs[:resolved], assigns(:complaint).resolved
    assert_equal attrs[:comments], assigns(:complaint).comments
  end
end
