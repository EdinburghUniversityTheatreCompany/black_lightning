# == Schema Information
#
# Table name: techies
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class TechieTest < ActionView::TestCase
  test "can set parents attributes" do
    techie = techies(:one)
    parent = techies(:two)

    attributes = { pineapple: { id: parent.id, _destroy: "0" } }

    techie.parents_attributes = attributes

    assert_includes techie.parents, parent
  end

  test "can set children attributes" do
    techie = techies(:one)
    child = techies(:two)

    attributes = { finbar: { id: child.id, _destroy: "0" } }

    techie.children_attributes = attributes

    assert_includes techie.children, child
  end

  test "cycle_through attribute can destroy" do
    techie = techies(:one)
    parent = techies(:two)

    techie.parents << parent

    assert_includes techie.parents, parent

    attributes = { "0" => { id: parent.id, _destroy: "1" } }

    techie.parents_attributes = attributes

    assert_not_includes techie.parents, parent
  end

  test "cycle_through attribute without id is ignored without crashing" do
    techie = techies(:one)
    child = techies(:two)

    attributes = {
      "0" => { id: "", _destroy: "0" },
      "1" => { id: child.id, _destroy: "0" }
    }

    techie.children_attributes = attributes

    assert_includes techie.children, child
  end

  test "get_relatives gets parents and children" do
    created_techies = FactoryBot.create_list(:techie, 10)

    base = created_techies.sample

    techies = base.get_relatives(3, false)
  end

  test "create relationships returns false if the line does not contain a >, and no techies are created." do
    assert_no_difference("Techie.count") do
      assert_raises(NoMethodError) do
        Techie.mass_create("name_1, name_2\n")
      end
    end
  end

  test "validates entry_year is a reasonable year" do
    techie = Techie.new(name: "Test Techie")

    techie.entry_year = 1949
    assert_not techie.valid?
    assert_includes techie.errors[:entry_year], "must be greater than 1950"

    techie.entry_year = Time.current.year + 2
    assert_not techie.valid?
    assert_includes techie.errors[:entry_year], "must be less than or equal to #{Time.current.year + 1}"

    techie.entry_year = 2020
    assert techie.valid?

    techie.entry_year = nil
    assert techie.valid?
  end
end
