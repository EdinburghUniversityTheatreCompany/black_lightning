require "test_helper"

class Admin::PermissionsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test "should get grid" do
    get :grid
    assert_response :success
  end

  test "grid excludes Reimbursements::CostCentre like its sibling reimbursements models" do
    get :grid
    assert_not_includes assigns(:models), Reimbursements::CostCentre,
      "CostCentre is managed via the Settings form + finance permission, not the per-model grid"
  end

  test "grid excludes Reimbursements::NominalCode like its sibling reimbursements models" do
    get :grid
    assert_not_includes assigns(:models), Reimbursements::NominalCode,
      "NominalCode is gated by the reimbursements permission, not the per-model grid"
  end

  test "grid offers the committee page permission as a miscellaneous row" do
    get :grid
    assert_select "input[name='[Committee][committee]access'][checked]", 1
    assert_select "input[name='[Member][committee]access']:not([checked])", 1
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

  test "should get role_grid" do
    get :role_grid, params: { id: roles(:committee).id }
    assert_response :success
  end

  test "grid offers the proposal review permission as a miscellaneous row" do
    get :grid
    assert_select "input[name='[Committee][proposals]review'][checked]", 1
    assert_select "input[name='[Member][proposals]review']:not([checked])", 1
  end

  test "saving the grid leaves stored permissions on subject classes the grid does not render alone" do
    # Admin::Proposals::Proposal is excluded from the model rows, so the grid offers no checkbox
    # for it — but rows from before it was excluded (2026-05-08) still exist in production, and
    # `manage` there is how a non-admin approves proposals. update_permission deletes every action
    # not submitted, so the class must never be in the list of subject classes the save walks.
    role = roles(:welfare)
    legacy = Admin::Permission.create!(action: "manage", subject_class: "Admin::Proposals::Proposal")
    role.permissions << legacy

    post :update_grid, params: { "[#{role.name}]" => { "Complaint" => { "read" => "read" } } }
    assert_redirected_to admin_permissions_path
    assert_includes role.reload.permissions, legacy, "A grid save wiped a stored proposal permission the grid never showed"

    post :update_role_grid, params: { id: role.id, "[#{role.name}]" => { "Complaint" => { "read" => "read" } } }
    assert_includes role.reload.permissions, legacy
  end

  test "Proposal Checker's permissions are managed in the grid like any other role" do
    role = Role.create!(name: "Proposal Checker")
    get :role_grid, params: { id: role.id }
    assert_response :success
  end

  test "role_grid for excluded role should redirect to role show" do
    get :role_grid, params: { id: roles(:admin).id }
    assert_redirected_to admin_role_path(roles(:admin))
  end

  test "should update role permissions via update_role_grid" do
    role = roles(:welfare)
    post :update_role_grid, params: { id: role.id }
    assert_redirected_to permissions_admin_role_path(role)
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

    role.reload
    assert_equal permissions_before, role.permissions.count
  end
end
