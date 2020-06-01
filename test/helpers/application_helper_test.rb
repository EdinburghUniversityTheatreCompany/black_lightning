require 'test_helper'

class ApplicationHelperTest < ActionView::TestCase
  test 'bool_icon' do
    assert_equal '&#10004;', bool_icon(true)
    assert_equal '&#10008;', bool_icon(false)
  end

  test 'bool_text' do
    assert_equal 'Yes', bool_text(true)
    assert_equal 'yes', bool_text('Pineapple', false)
    assert_equal 'no', bool_text(false, false)
    assert_equal 'No', bool_text(nil, true)
    assert_equal 'Yes', bool_text('')
    assert_equal 'Yes', bool_text([])
  end

  test 'html_alert_info' do
    assert_equal ['alert-danger', 'fas fa-exclamation-circle'], html_alert_info(:alert)
    assert_equal ['alert-danger', 'fas fa-exclamation-circle'], html_alert_info(:error)
    assert_equal ['alert-success', 'fas fa-check-circle'], html_alert_info(:success)
    assert_equal ['alert-info', 'fas fa-info-circle'], html_alert_info(:notice)
    assert_equal ['', ''], html_alert_info(:pineapple)
  end

  test 'current environment' do
    skip 'I do not know how. Requires a request to be present.'
  end

  test 'append to flash' do
    assert_nil flash[:error]

    append_to_flash(:error, 'Pineapple')
    assert_equal flash[:error], ['Pineapple']

    append_to_flash(:error, 'Hexagon')
    assert_equal flash[:error], %w[Pineapple Hexagon]

    flash[:error] = 'Viking'
    assert_equal flash[:error], 'Viking'

    append_to_flash(:error, 'Donkey')
    assert_equal flash[:error], %w[Viking Donkey]
  end

  test 'merge hash' do
    a = {
      ingredients: [:pineapple],
      jobs: [:chef]
    }

    b = {
      ingredients: [:cheese, :pineapple],
      jobs: [:techie],
      lead: 'Finbar the Viking'
    }

    result = {
      ingredients: [:pineapple, :cheese],
      jobs: [:chef, :techie],
      lead: 'Finbar the Viking'
    }

    assert_equal result, merge_hash(a, b)
  end

  test 'Get xts_widget' do
    id = 2139
    assert_match id.to_s, xts_widget(id)
  end

  test 'Get spark_seat_widget' do
    slug = 'hexagon-finbar-pineapple-red'
    assert_match slug, spark_seat_widget(slug)
  end

  # We now use the built-in function, but it is still good to test it
  test 'Get strip_tags' do
    assert_equal 'This is stripped', strip_tags('<!-- it happened 2 years before 1980, idk when exactly -->This is stripped')
    assert_equal 'This is stripped', strip_tags('<div><span title="hello world!">This is stripped</div>')
  end
end
