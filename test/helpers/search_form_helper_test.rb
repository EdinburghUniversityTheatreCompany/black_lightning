require "test_helper"

class SearchFormHelperTest < ActionView::TestCase
  tests SearchFormHelper

  # A fake form builder that records what `render_search_form_field` hands to `f.input`.
  # The leak these tests guard is invisible in the rendered HTML — simple_form drops
  # options it doesn't recognise — so the observable is the options hash itself.
  class RecordingBuilder
    attr_reader :key, :options

    def input(key, options)
      @key = key
      @options = options
      ""
    end
  end

  # The field-config hash carries two keys that are ours, not simple_form's: `:type` picks
  # which renderer to use, `:slug` the i18n key for the label. Both have to be stripped
  # before the rest of the hash is passed on. `Hash#except!` takes varargs, so the old
  # `except!([ :type, :slug ])` deleted the key `[:type, :slug]` — which never exists — and
  # stripped nothing.
  test "does not pass the config-only :type and :slug keys to the input" do
    builder = RecordingBuilder.new

    render_search_form_field(builder, :name_cont, { type: :text, slug: "defaults.name" })

    assert_not_includes builder.options.keys, :type
    assert_not_includes builder.options.keys, :slug
  end

  test "keeps the options the input does need" do
    builder = RecordingBuilder.new

    render_search_form_field(builder, :name_cont, { slug: "defaults.name" })

    assert_equal I18n.t("simple_form.labels.defaults.name"), builder.options[:label]
    refute builder.options[:required], "search fields are never required"
  end

  # `except` (unlike `except!`) leaves the caller's config hash alone. The configs are
  # rebuilt per render today, so this is insurance rather than a live bug.
  test "leaves the caller's field config hash intact" do
    config = { type: :text, slug: "defaults.name" }

    render_search_form_field(RecordingBuilder.new, :name_cont, config)

    assert_equal :text, config[:type]
    assert_equal "defaults.name", config[:slug]
  end

  # And the real simple_form path still renders: a :select config renders a <select>.
  test "a select config renders a select through simple_form" do
    html = nil
    view.search_form_for(Company.ransack({}), builder: SimpleForm::FormBuilder, url: "/") do |f|
      html = render_search_form_field(f, :name_cont, { type: :select, collection: %w[Alice Bob] })
    end

    assert_match(/<select/, html)
    assert_match(/<label/, html)
  end
end
