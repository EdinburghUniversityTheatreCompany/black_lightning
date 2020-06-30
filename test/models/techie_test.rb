require 'test_helper'

class TechieTest < ActionView::TestCase
  test 'can set parents attributes' do
    techie = techies(:one)
    parent = techies(:two)

    attributes = { pineapple: { id: parent.id, _destroy: '0' } }

    techie.parents_attributes = attributes

    assert_includes techie.parents, parent
  end

  test 'can set children attributes' do
    techie = techies(:one)
    child = techies(:two)

    attributes = { finbar: { id: child.id, _destroy: '0' } }

    techie.children_attributes = attributes

    assert_includes techie.children, child
  end

  test 'cycle_through attribute can destroy' do
    techie = techies(:one)
    parent = techies(:two)

    techie.parents << parent
  
    assert_includes techie.parents, parent

    attributes = { '0' => { id: parent.id, _destroy: '1' } }

    techie.parents_attributes = attributes

    assert_not_includes techie.parents, parent
  end

  test 'cycle_through attribute without id is ignored without crashing' do
    techie = techies(:one)
    child = techies(:two)

    attributes = { 
      '0' => { id: '', _destroy: '0' },
      '1' => { id: child.id, _destroy: '0' },
    }

    techie.children_attributes = attributes

    assert_includes techie.children, child
  end
end
