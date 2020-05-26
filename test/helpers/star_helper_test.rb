require 'test_helper'

class StarHelperTest < ActionView::TestCase
  test 'star rating' do
    assert_equal '', star_rating('')
    assert_equal '', star_rating(nil)

    star = '<i class="fas fa-star" aria-hidden=”true”></i>'
    half_star = '<i class="fas fa-star-half-alt" aria-hidden=”true”></i>'

    assert_equal half_star, star_rating(0.5)

    assert_equal "#{star}#{star}#{star}", star_rating(3)
    assert_equal "#{star}#{star}#{star}#{half_star}", star_rating('3.3')
    assert_equal "#{star}#{star}#{star}#{half_star}", star_rating('3.7')
  end
end
