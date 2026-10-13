require "test_helper"

class SearchFormHelperTest < ActionView::TestCase
  tests SearchFormHelper

  # Records what `render_search_form_field` hands to `f.input`. simple_form drops options it does
  # not recognise, so the leak is invisible in the HTML and the options hash is the observable.
  class RecordingBuilder
    attr_reader :key, :options

    def input(key, options)
      @key = key
      @options = options
      ""
    end
  end

  # :type and :slug are ours, not simple_form's. `except!` takes varargs, so the old
  # `except!([ :type, :slug ])` deleted the key [:type, :slug], which never exists, and stripped nothing.
  test "does not pass the config-only :type and :slug keys to the input, or change the caller's hash" do
    builder = RecordingBuilder.new
    config = { type: :text, slug: "defaults.name" }

    render_search_form_field(builder, :name_cont, config)

    assert_not_includes builder.options.keys, :type
    assert_not_includes builder.options.keys, :slug
    assert_equal({ type: :text, slug: "defaults.name" }, config.slice(:type, :slug))
  end

  test "keeps the options the input does need" do
    builder = RecordingBuilder.new

    render_search_form_field(builder, :name_cont, { slug: "defaults.name" })

    assert_equal I18n.t("simple_form.labels.defaults.name"), builder.options[:label]
    refute builder.options[:required], "search fields are never required"
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
