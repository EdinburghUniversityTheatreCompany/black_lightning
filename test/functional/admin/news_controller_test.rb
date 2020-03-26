require 'test_helper'

class Admin::NewsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should get index' do
    FactoryBot.create_list(:news, 10)

    get :index
    assert_response :success
  end

  test 'should get show' do
    @news = FactoryBot.create(:news)

    get :show, params: { id: @news}
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create news' do
    attrs = FactoryBot.attributes_for(:news)

    assert_difference('News.count') do
      post :create, news: attrs
    end

    assert_redirected_to admin_news_path(assigns(:news))
  end

  test 'should get edit' do
    @news = FactoryBot.create(:news)

    get :edit, params: { id: @news}
    assert_response :success
  end

  test 'should update news' do
    @news = FactoryBot.create(:news)
    attrs = FactoryBot.attributes_for(:news)

    put :update, params: { id: @news, news: attrs}
    assert_redirected_to admin_news_path(assigns(:news))
  end

  test 'should destroy news' do
    @news = FactoryBot.create(:news)

    assert_difference('News.count', -1) do
      delete :destroy, params: { id: @news}
    end

    assert_redirected_to admin_news_index_path
  end
end
