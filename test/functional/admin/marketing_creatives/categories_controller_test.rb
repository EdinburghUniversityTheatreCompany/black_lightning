require 'test_helper'

class Admin::MarketingCreatives::CategoriesControllerTest < ActionController::TestCase
  setup do
    @admin = users(:admin)
    sign_in @admin

    @category = FactoryBot.create(:marketing_creatives_category)
  end

  test 'should get index' do
    categories = FactoryBot.create_list(:marketing_creatives_category, 3)
    get :index

    assert_response :success
    assert_not_nil assigns(:categories)

    categories.each do |category|
      assert_includes response.body, category.name
    end
  end

  test 'should get show' do
    category_infos = FactoryBot.create_list(:marketing_creatives_category_info, 3, category: @category)

    get :show, params: { id: @category }

    assert_response :success

    assert_equal category_infos.collect(&:id).sort, assigns(:category_infos).collect(&:id).sort

    category_infos.each do |category_info|
      assert_includes response.body, category_info.profile.name
    end
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create category' do
    attributes = FactoryBot.attributes_for(:marketing_creatives_category)
  
    assert_difference('MarketingCreatives::Category.count') do
      post :create, params: { marketing_creatives_category: attributes }
    end

    assert MarketingCreatives::Category.where(name: attributes[:name]).one?

    assert_redirected_to admin_marketing_creatives_category_path(assigns(:category))
  end

  test 'should not create invalid category' do
    attributes = FactoryBot.attributes_for(:marketing_creatives_category)
    attributes[:name] = nil

    assert_no_difference('MarketingCreatives::Category.count') do
      post :create, params: { marketing_creatives_category: attributes }
    end
  
    assert_response :unprocessable_entity
  end

  test 'should not create category info for the same category/profile combination twice' do
    profile = FactoryBot.create(:marketing_creatives_profile)

    existing_category_info = FactoryBot.attributes_for(:marketing_creatives_category_info, profile: profile)

    attributes = FactoryBot.attributes_for(:marketing_creatives_category_info, profile: profile)

    assert_no_difference('MarketingCreatives::Category.count') do
      post :create, params: { marketing_creatives_category: attributes }
    end
  end

  test 'should get edit' do
    get :edit, params: { id: @category }

    assert_response :success
  end

  test 'should update category' do
    attributes = FactoryBot.attributes_for(:marketing_creatives_category)
  
    put :update, params: { id: @category, marketing_creatives_category: attributes }

    assert attributes[:name], assigns(:category).name
    assert_redirected_to admin_marketing_creatives_category_path(@category)
  end
  
  test 'should not update invalid role' do
    attributes = FactoryBot.attributes_for(:marketing_creatives_category)
    attributes[:name] = nil

    put :update, params: { id: @category, marketing_creatives_category: attributes }

    assert_not_equal @category.name_on_profile, attributes[:name_on_profile]

    assert_response :unprocessable_entity
  end

  test 'should destroy category' do
    assert_difference('MarketingCreatives::Category.count', -1) do
      delete :destroy, params: { id: @category }
    end

    assert_redirected_to admin_marketing_creatives_categories_path
  end

  test 'should not destroy category with attached infos' do
    category_info = FactoryBot.create(:marketing_creatives_category_info, category: @category)

    assert_no_difference('MarketingCreatives::Category.count') do
      delete :destroy, params: { id: @category }
    end

    assert_redirected_to admin_marketing_creatives_category_path(@category)
  end
end
