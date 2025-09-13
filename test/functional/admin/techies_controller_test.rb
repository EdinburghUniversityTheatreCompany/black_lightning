require "test_helper"

class Admin::TechiesControllerTest < ActionController::TestCase
  setup do
    @admin = users(:admin)
    sign_in @admin

    @techie = techies(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get show" do
    get :show, params: { id: @techie.id }
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end


  test "should get mass new" do
    get :mass_new
    assert_response :success
  end

  # Also tests if the association stuff works.
  test "should create" do
    child = techies(:one)
    parent = techies(:two)

    attributes = {
      name: "Brian Brocolli",
      parents_attributes: { "0" => { id: parent.id, "_destroy" => "false" } },
      children_attributes: { "1" => { id: child.id, "_destroy" => "false" } }
    }

    assert_difference "Techie.count" do
      post :create, params: { techie: attributes }
    end

    assert child.parents.first, assigns(:techie)
    assert parent.children.first, assigns(:techie)

    assert_redirected_to admin_techie_path(assigns(:techie))
  end

  test "should not create invalid" do
    attributes = { name: "" }

    assert_no_difference "Techie.count" do
      post :create, params: { techie: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should mass create" do
    relationships_data = "parent_1, parent_2 > child_1, child_2, child_3\nFinbar the Viking > child_4, child_5"

    # Should create all parents and children except for Finbar, who already exists.
    assert_difference("Techie.count", 7) do
      post :mass_create, params: { techie: { relationships_data: relationships_data } }
    end

    parent_1 = Techie.find_by(name: "parent_1")
    parent_2 = Techie.find_by(name: "parent_2")
    parent_3 = Techie.find_by(name: "Finbar the Viking")
    child_1 = Techie.find_by(name: "child_1")
    child_2 = Techie.find_by(name: "child_2")
    child_3 = Techie.find_by(name: "child_3")
    child_4 = Techie.find_by(name: "child_4")
    child_5 = Techie.find_by(name: "child_5")

    assert_not_nil parent_1
    assert_not_nil parent_2
    assert_not_nil parent_3
    assert_not_nil child_1
    assert_not_nil child_2
    assert_not_nil child_3
    assert_not_nil child_4
    assert_not_nil child_5

    assert_includes parent_1.children, child_1
    assert_includes parent_1.children, child_2
    assert_includes parent_1.children, child_3
    assert_includes parent_2.children, child_1
    assert_includes parent_2.children, child_2
    assert_includes parent_2.children, child_3
    assert_includes parent_3.children, child_4
    assert_includes parent_3.children, child_5
  end

  test "should get edit" do
    get :edit, params: { id: @techie.id }
    assert_response :success
  end

  test "should update" do
    attributes = { name: "Brian Brocolli" }

    patch :update, params: { id: @techie.id, techie: attributes }

    assert attributes[:name], assigns(:techie).name
    assert_redirected_to admin_techie_path(assigns(:techie))
  end

  test "should not update invalid" do
    attributes = { name: nil }

    patch :update, params: { id: @techie.id, techie: attributes }

    assert_response :unprocessable_entity
  end

  test "should destroy" do
    assert_difference "Techie.count", -1 do
      delete :destroy, params: { id: techies(:two).id }
    end

    assert_redirected_to admin_techies_path
  end

  test "should get tree" do
    get :tree
    assert_response :success
  end

  test "should get tree data" do
    get :tree_data

    assert_response :success

    json = JSON.parse(response.body)

    assert json.is_a? Hash
    assert json.key? "nodes"
    assert json.key? "edges"
  end

  test "should get bush" do
    get :bush
    assert_response :success
  end

  test "should get bush with one base techie" do
    get :bush, params: { q: { id_eq: Techie.all.last } }
    assert_response :success
  end

  test "should get tree if you have index permission" do
    sign_out @admin
    sign_in users(:committee)

    get :tree
    assert_response :success
  end

  test "should get by_entry_year" do
    get :by_entry_year
    assert_response :success
    assert_not_nil assigns(:title)
    assert_not_nil assigns(:grouped_data)
  end

  test "by_entry_year groups techies correctly by parents" do
    # Create test data with specific entry years and parent relationships
    parent1 = Techie.create!(name: "Alice", entry_year: 2020)
    parent2 = Techie.create!(name: "Bob", entry_year: 2019)
    child1 = Techie.create!(name: "Charlie", entry_year: 2021)
    child2 = Techie.create!(name: "Diana", entry_year: 2021)
    child3 = Techie.create!(name: "Eve", entry_year: 2021)

    # Set up parent relationships
    child1.parents = [parent1]
    child2.parents = [parent1, parent2]
    child3.parents = [parent2]

    get :by_entry_year

    assert_response :success
    grouped_data = assigns(:grouped_data)

    # Check that 2021 year data contains proper parent groupings
    year_2021_data = grouped_data[2021]
    assert_not_nil year_2021_data

    # Should have three parent groups with entry years: "Alice (2020)", "Alice (2020) & Bob (2019)", "Bob (2019)"
    parent_groups = year_2021_data.keys.sort
    assert_includes parent_groups, "Alice (2020)"
    assert_includes parent_groups, "Alice (2020) & Bob (2019)"
    assert_includes parent_groups, "Bob (2019)"

    # Check correct techies are in each group
    assert_includes year_2021_data["Alice (2020)"].map(&:name), "Charlie"
    assert_includes year_2021_data["Alice (2020) & Bob (2019)"].map(&:name), "Diana"
    assert_includes year_2021_data["Bob (2019)"].map(&:name), "Eve"
  end
end
