require 'test_helper'

class Admin::NewsControllerTest < ActionController::TestCase
  setup do
    @news = news(:one)
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user

    @user = users(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get show" do
    get :show, id: @user
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create news" do
    #Remove the existing entry:
    News.find(@news).destroy

    assert_difference('News.count') do
      post :create, news: { title: @news.title, body: @news.body, slug: @news.slug, publish_date: @news.publish_date, show_public: @news.show_public }
    end

    assert_redirected_to admin_news_path(assigns(:news))
  end

  test "should get edit" do
    get :edit, id: @user
    assert_response :success
  end

  test "should update news" do
    put :update, id: @news, news: { title: @news.title, body: @news.body, slug: @news.slug, publish_date: @news.publish_date, show_public: @news.show_public }
    assert_redirected_to admin_news_path(@news)
  end

  test "should destroy news" do
    assert_difference('News.count', -1) do
      delete :destroy, id: @news
    end

    assert_redirected_to admin_news_index_path
  end
end
