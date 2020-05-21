require 'test_helper'

class Admin::NewsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @news = FactoryBot.create(:news)
  end

  test 'should get index' do
    FactoryBot.create_list(:news, 10)

    get :index
    assert_response :success

    assert_not_nil assigns(:news)
  end

  test 'should get show' do
    get :show, params: { id: @news}
    assert_response :success

    assert_not_nil assigns(:news)
  end

  test 'should get new' do
    get :new
    assert_response :success

    assert_not_nil assigns(:news)
  end

  test 'should create news' do
    attrs = FactoryBot.attributes_for(:news)

    assert_difference('News.count') do
      post :create, params: { news: attrs }
    end

    assert_redirected_to admin_news_path(assigns(:news))
  end

  test 'should not create news that is invalid' do
    attrs = FactoryBot.attributes_for(:news, body: '')

    assert_no_difference('News.count') do
      post :create, params: { news: attrs }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @news }

    assert_response :success
  end

  test 'should update news' do
    attrs = FactoryBot.attributes_for(:news)

    put :update, params: { id: @news, news: attrs }

    assert_redirected_to admin_news_path(assigns(:news))
  end

  test 'should not update news that is invalid' do
    attrs = FactoryBot.attributes_for(:news, title: '')

    put :update, params: { id: @news, news: attrs }

    assert_response :unprocessable_entity
  end

  test 'should destroy news' do
    assert_difference('News.count', -1) do
      delete :destroy, params: { id: @news}
    end

    assert_redirected_to admin_news_index_path
  end
end
