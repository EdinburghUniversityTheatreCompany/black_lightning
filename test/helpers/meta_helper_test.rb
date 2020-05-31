require 'test_helper'

class MetaHelperTest < ActionView::TestCase
  test 'test meta tags generator' do
    @meta = {
      description: 'Hexagon',
      'fb:test' => 'Finbar',
      array_tags: %w[Dennis Donkey]
    }
    result = "<meta name='description' content='Hexagon' />\n<meta property='fb:test' content='Finbar' />\n<meta name='array_tags' content='Dennis' />\n<meta name='array_tags' content='Donkey' />\n<meta property='og:description' content='Hexagon' />"
    assert_equal result, meta_tags(@meta)
  end

  test 'uses description as default for og:description' do
    @meta = { description: 'Hexagon' }

    assert_equal "<meta name='description' content='Hexagon' />\n<meta property='og:description' content='Hexagon' />", meta_tags(@meta)

    @meta['og:description'] = 'Pineapple'

    assert_equal "<meta name='description' content='Hexagon' />\n<meta property='og:description' content='Pineapple' />", meta_tags(@meta)
  end
end
