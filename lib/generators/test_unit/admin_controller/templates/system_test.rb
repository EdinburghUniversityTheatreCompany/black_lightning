require 'application_system_test_case'

<%- human_resource_name = resource_name.humanize %>
<% module_namespacing do -%>
class <%= class_name.pluralize %>Test < ApplicationSystemTestCase
  setup do
    @<%= singular_table_name %> = <%= fixture_name.gsub('admin_', '') %>(:one)
    login_as users(:admin)
  end

  test "visiting the index" do
    visit <%= plural_table_name %>_url
    assert_selector "h1", text: "<%= human_resource_name.pluralize.titleize %>"

    assert_text "REPLACE THIS WITH THE NAME OF A FIXTURE ITEM"
  end

  test "should create <%= human_resource_name %>" do
    visit <%= plural_table_name %>_url
    click_on "New <%= human_resource_name.titleize %>"

    <%- attributes_hash.each do |attr, value| -%>
    <%- if boolean?(attr) -%>
    check "<%= attr.humanize %>" if <%= value %>
    <%- else -%>
    fill_in "<%= attr.humanize %>", with: <%= value %>
    <%- end -%>
    <%- end -%>
    click_on "Create <%= human_resource_name %>"

    assert_text 'The <%= human_resource_name %> was successfully created'
  end

  test "should update <%= human_resource_name %>" do
    visit <%= singular_table_name %>_url(@<%= singular_table_name %>)
    click_on "Edit", match: :prefer_exact

    <%- attributes_hash.each do |attr, value| -%>
    <%- if boolean?(attr) -%>
    check "<%= attr.humanize %>" if <%= value %>
    <%- else -%>
    fill_in "<%= attr.humanize %>", with: <%= value %>
    <%- end -%>
    <%- end -%>
    click_on "Update <%= human_resource_name %>"

    assert_text "The <%= human_resource_name %> was successfully updated."
  end

  test "should destroy <%= human_resource_name %>" do
    visit <%= singular_table_name %>_url(@<%= singular_table_name %>)

    page.accept_confirm do
      click_on 'Destroy', match: :first
    end
    assert_text "The <%= human_resource_name %> has been successfully destroyed."
  end
end
<% end -%>