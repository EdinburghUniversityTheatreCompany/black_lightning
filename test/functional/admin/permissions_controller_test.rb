require "test_helper"

class Admin::PermissionsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test "should get grid" do
    get :grid
    assert_response :success
  end

  test "grid leaves out the finance-gated reimbursements models" do
    get :grid
    [ Reimbursements::CostCentre, Reimbursements::NominalCode ].each do |model|
      assert_not_includes assigns(:models), model, "#{model} is managed by finance permissions and Settings, not the per-model grid"
    end
  end

  test "grid offers miscellaneous permissions as rows" do
    get :grid
    { "committee" => "access", "proposals" => "review" }.each do |subject, action|
      assert_select "input[name='[Committee][#{subject}]#{action}'][checked]", 1
      assert_select "input[name='[Member][#{subject}]#{action}']:not([checked])", 1
    end
  end

  test "should update permissions" do
    post :update_grid
    assert_redirected_to admin_permissions_path
  end

  test "submitting empty params should not wipe existing permissions" do
    role = roles(:committee)
    permissions_before = role.permissions.count

    assert permissions_before > 0, "Committee should have permissions to start with"

    post :update_grid

    role.reload
    permissions_after = role.permissions.count

    assert_equal permissions_before, permissions_after, "Permissions should not be wiped when no data is submitted for a role"
  end

  test "submitting permissions for a role should save them" do
    role = roles(:welfare)

    assert role.permissions.where(subject_class: "Complaint").exists?

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

  test "should get role_grid" do
    get :role_grid, params: { id: roles(:committee).id }
    assert_response :success
  end

  test "saving the grid leaves stored permissions on subject classes the grid does not render alone" do
    # The grid offers no checkbox for Proposal, and update_permission deletes every action not
    # submitted, so the class must never be in the subject list a save walks (stored `manage` rows
    # are how non-admins approve proposals).
    role = roles(:welfare)
    legacy = Admin::Permission.create!(action: "manage", subject_class: "Admin::Proposals::Proposal")
    role.permissions << legacy

    post :update_grid, params: { "[#{role.name}]" => { "Complaint" => { "read" => "read" } } }
    assert_redirected_to admin_permissions_path
    assert_includes role.reload.permissions, legacy, "A grid save wiped a stored proposal permission the grid never showed"

    post :update_role_grid, params: { id: role.id, "[#{role.name}]" => { "Complaint" => { "read" => "read" } } }
    assert_includes role.reload.permissions, legacy
  end

  test "role_grid for excluded role should redirect to role show" do
    get :role_grid, params: { id: roles(:admin).id }
    assert_redirected_to admin_role_path(roles(:admin))
  end

  test "submitting role permissions should save them" do
    role = roles(:welfare)

    post :update_role_grid, params: {
      id: role.id,
      "[#{role.name}]" => {
        "Complaint" => { "read" => "read", "manage" => "manage" }
      }
    }

    assert_redirected_to permissions_admin_role_path(role)

    role.reload
    complaint_permissions = role.permissions.where(subject_class: "Complaint").pluck(:action).sort
    assert_includes complaint_permissions, "manage"
    assert_includes complaint_permissions, "read"
  end

  test "submitting empty role params should not wipe existing permissions" do
    role = roles(:committee)
    permissions_before = role.permissions.count

    assert permissions_before > 0, "Committee should have permissions to start with"

    post :update_role_grid, params: { id: role.id }

    assert_redirected_to permissions_admin_role_path(role)
    assert_equal permissions_before, role.reload.permissions.count
  end
end
