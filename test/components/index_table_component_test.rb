require "test_helper"

class IndexTableComponentTest < ViewComponent::TestCase
  # The component asks `can?`, which reaches through Devise for the current
  # user. Devise's ControllerHelpers wants a controller test's @request, which
  # a component test has no equivalent of, so warden goes on by hand.
  setup do
    env = vc_test_controller.request.env
    env["warden"] = Warden::Proxy.new(env, Warden::Manager.new(nil)).tap do |proxy|
      proxy.set_user(users(:admin), scope: :user, store: false)
    end
  end

  def event = @event ||= FactoryBot.create(:show)

  def spec
    { headers: [ :name ], field_sets: [ { fields: [ event ] } ], resource_class: Show }
  end

  test "the record becomes a link to itself" do
    render_inline(IndexTableComponent.new(**spec))

    assert_selector "tbody td a", text: event.name
  end

  # A caller that does not want the link still has to pass the record, because
  # it is what the edit permission is checked against — so it gets dropped
  # rather than printed raw.
  test "with the item link off, the record cell is dropped rather than printed" do
    render_inline(IndexTableComponent.new(**spec, include_link_to_item: false))

    assert_no_text event.name
  end

  # The bug the partial had: it appended into the caller's own arrays, so the
  # same spec rendered twice grew a second Edit button and a re-wrapped cell.
  test "rendering the same spec twice is stable, and never writes to the caller" do
    shared = spec

    render_inline(IndexTableComponent.new(**shared))
    first = page.native.to_html

    render_inline(IndexTableComponent.new(**shared))
    second = page.native.to_html

    assert_equal first, second
    assert_equal [ :name ], shared[:headers], "the caller's headers were written to"
    assert_equal [ event ], shared[:field_sets].first[:fields], "the caller's field_sets were written to"
  end
end
