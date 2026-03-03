require "test_helper"

class Admin::PermissionsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test "should get grid" do
    get :grid
    assert_response :success
  end

  test "should update permissions" do
    post :update_grid
    assert_redirected_to admin_permissions_path
  end

  test "submitting empty params should not wipe existing permissions" do
    role = roles(:committee)
    permissions_before = role.permissions.count

    assert permissions_before > 0, "Committee should have permissions to start with"

    # Simulate submitting the form with no checkbox data (e.g. page not fully loaded)
    post :update_grid

    role.reload
    permissions_after = role.permissions.count

    assert_equal permissions_before, permissions_after, "Permissions should not be wiped when no data is submitted for a role"
  end

  test "submitting permissions for a role should save them" do
    role = roles(:welfare)

    # Welfare starts with read+update on Complaint (from fixtures)
    assert role.permissions.where(subject_class: "Complaint").exists?

    # Submit with Complaint manage permission added
    post :update_grid, params: {
      "[#{role.name}]" => {
        "Complaint" => { "read" => "read", "update" => "update", "manage" => "manage" }
      }
    }

    assert_redirected_to admin_permissions_path

    role.reload
    complaint_permissions = role.permissions.where(subject_class: "Complaint").pluck(:action).sort

    assert_includes complaint_permissions, "manage"
    assert_includes complaint_permissions, "read"
    assert_includes complaint_permissions, "update"
  end
end
