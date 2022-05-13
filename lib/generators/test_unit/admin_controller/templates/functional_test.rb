require 'application_integration_test'
<%- index_url = plural_table_name + '_url' %>

<%- module_namespacing do -%>
<%- controller_name = controller_class_name + 'ControllerTest' %>
<%- controller_name = 'Admin::' + controller_class_name unless controller_name.starts_with?('Admin::') %>
<% class_name = controller_class_name.gsub('Admin::', '').singularize %>

class <%= controller_name %> < ApplicationIntegrationTest
  <%- if mountable_engine? -%>
  include Engine.routes.url_helpers

  <%- end -%>
  setup do
    @<%= singular_table_name %> = <%= fixture_name.gsub('admin_', '') %>(:one)

    login_as users(:admin)

    # You must update these to not directly copy the fixture but put in original data.
    @params = { 
      <%= "#{singular_table_name.gsub('admin_', '')}: {#{attributes_string } }" %> 
    }
  end

  test 'should get index' do
    get <%= index_url %>
    assert_response :success
    assert_not_nil assigns(:<%= resource_name.pluralize %>)
  end

  test 'should get new' do
    get <%= new_helper %>
    assert_response :success
  end

  test 'should create <%= resource_name %>' do
    assert_difference('<%= class_name %>.count') do
      post <%= index_url %>, params: @params
    end

    assert_redirected_to <%= show_helper.gsub("@#{singular_table_name}", "assigns(:#{resource_name})") %>
  end

  test 'should not create <%= resource_name %> when invalid' do
    assert_no_difference('<%= class_name %>.count') do
      post <%= index_url %>, params: @params
    end

    assert_response :unprocessable_entity
  end

  test 'should show <%= resource_name %>' do
    get <%= show_helper %>
    assert_response :success
  end

  test 'should get edit' do
    get <%= edit_helper %>
    assert_response :success
  end

  test 'should update <%= resource_name %>' do
    patch <%= show_helper %>, params: @params
    assert_redirected_to <%= show_helper %>
  end

  test 'should not update <%= resource_name %> when invalid' do
    patch <%= show_helper %>, params: @params
    assert_response :unprocessable_entity
  end

  test 'should destroy <%= resource_name %>' do
    assert_difference('<%= class_name %>.count', -1) do
      delete <%= show_helper %>
    end

    assert_redirected_to <%= index_url %>
  end
end
<% end -%>
