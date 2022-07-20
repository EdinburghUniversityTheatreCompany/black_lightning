require 'test_helper'

class LabelHelperTest < ActionView::TestCase
  test 'raises error when passing nil as class' do
    assert_raises ArgumentError do
      generate_label nil, 'Hexagon'
    end
  end

  test 'raises error when passing nothing as class' do
    assert_raises ArgumentError do
      generate_label nil, ''
    end
  end

  test 'raises error when passing hexagon as class' do
    assert_raises ArgumentError do
      generate_label 'Hexagon', 'Pineapple'
    end
  end

  test 'sanitizes html' do
    message = '<faketag>Finbar<div> the <p></p>Viking'
    label = generate_label('info', message)
    assert_equal '<span style="margin-right: 5px;" class="label label-info">Finbar<div> the <p></p>Viking</div></span>', label
  end

  test 'returns label' do
    label = generate_label('danger', "It's dangerous to go alone!")
    assert_equal '<span style="margin-right: 5px;" class="label label-important">It\'s dangerous to go alone!</span>', label
  end

  test 'returns label with float-right' do
    label = generate_label(:success, 'You did it!', true)
    assert_equal '<span style="margin-right: 5px;" class="label label-success float-right">You did it!</span>', label
  end
end
