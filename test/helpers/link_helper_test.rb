require 'test_helper'

class LinkHelperTest < ActionView::TestCase
  include NameHelper

  def current_ability
    @current_user.ability
  end

  setup do
    @current_user = users(:admin)
  end

  test 'user_link for nil' do
    assert_equal 'User Not Found', user_link(nil, true)

    @current_user = users(:user)

    assert_equal 'User Not Found', user_link(nil, false)
  end

  test 'user_link without permission' do
    @current_user = users(:user)
  
    assert_equal 'Peter Peanut', user_link(users(:admin), true)
  end

  test 'user_link with public profile' do
    @current_user = users(:user)

    target = FactoryBot.create(:user, public_profile: true, first_name: 'Dennis', last_name: 'the Donkey')

    assert_equal "<a href=\"/users/#{target.id}\">Dennis the Donkey</a>", user_link(target, true)

    assert_equal 'Dennis the Donkey', user_link(target, false)

    target.public_profile = false
    assert_equal 'Dennis the Donkey', user_link(target, true)
  end

  test 'user_link as admin' do
    assert_equal '<a href="/admin/users/1">Peter Peanut</a>', user_link(users(:admin), true)
  end

  test 'link_to_add' do
    skip "Needs a form passed, but I don't know how to create one in here. Test is not essential as every nested form will break when the function breaks, so you will notice, and it has coverage."
    
    techie = techies(:one)

    simple_nested_form_for [:admin, techie] do |form|
      assert_equal '', link_to_add(form, :parents)
    end
  end

  test 'link_to_remove' do
    skip "Needs a form passed, but I don't know how to create one in here. Test is not essential as every nested form will break when the function breaks, so you will notice, and it has coverage."

    techie = techies(:one)

    simple_nested_form_for [:admin, techie] do |form|
      assert_equal '', link_to_remove(form, :parents)
    end
  end

  test 'remove_button_text' do
    default_remove_button_text = '<i class="fa fa-trash" aria-hidden="true"></i> Remove'.html_safe
    assert_equal default_remove_button_text, remove_button_text

    other_remove_button_text = '<i class="fa fa-trash" aria-hidden="true"></i> Pineapple'.html_safe

    assert_equal other_remove_button_text, remove_button_text('Pineapple')
  end

  test 'get_link with index' do
    expected_link = '<a class="btn btn-secondary" title="Show All Fault Reports" data-method="get" href="/admin/fault_reports"><span class="no-wrap"><i class="fa fa-th-list" aria-hidden=”true”></i> Show All</span> Fault Reports</a>'

    assert_equal expected_link, get_link(FaultReport, :index)

    assert_raises TypeError do
      get_link(FaultReport.new, :index)
    end
  end

  test 'get_link with show' do
    proposal_call = FactoryBot.create(:proposal_call, id: 1, name: 'Dionysia Proposals')
    expected_link = '<a class="" title="Dionysia Proposals" data-method="get" href="/admin/proposals/calls/1">Dionysia Proposals</a>'

    assert_equal expected_link, get_link(proposal_call, :show)

    assert_raises TypeError do
      get_link(FaultReport, :show)
    end
  end

  test 'get_link with new' do
    expected_link = '<a class="btn btn-primary" title="New Maintenance Debt" data-method="get" href="/admin/maintenance_debts/new"><span class="no-wrap"><i class="fa fa-plus" aria-hidden=”true”></i> New</span> Maintenance Debt</a>'

    assert_equal expected_link, get_link(Admin::MaintenanceDebt, :new)

    assert_raises TypeError do
      get_link(Admin::MaintenanceDebt.new, :new)
    end
  end

  test 'get_link with edit with no_wrap' do
    staffing = FactoryBot.create(:staffing, id: 1)
    expected_link = '<a class="btn no-wrap" title="Edit" data-method="get" href="/admin/staffings/1/edit"><span class="no-wrap"><i class="fa fa-pencil-alt" aria-hidden=”true”></i> Edit</span></a>'

    assert_equal expected_link, get_link(staffing, :edit, no_wrap: true)

    assert_raises TypeError do
      get_link(Opportunity, :edit)
    end
  end

  test 'get_link with destroy' do
    news = FactoryBot.create(:news, id: 1, title: 'Vikings have taken over the Bedlam')
    expected_link = '<a class="btn btn-danger" data-title="Deleting the News &quot;Vikings have taken over the Bedlam&quot;" data-confirm="Are you sure you want to delete the News &quot;Vikings have taken over the Bedlam&quot;?" title="Destroy" rel="nofollow" data-method="delete" href="/admin/news/1-vikings-have-taken-over-the-bedlam"><span class="no-wrap"><i class="fa fa-trash" aria-hidden=”true”></i> Destroy</span></a>'

    assert_equal expected_link, get_link(news, :destroy)

    assert_raises TypeError do
      get_link(Admin::StaffingDebt, :destroy)
    end
  end

  test 'get_link with approve' do
    news = FactoryBot.create(:opportunity, id: 1)
    expected_link = '<a class="btn btn-success" title="Approve" rel="nofollow" data-method="put" href="/admin/opportunities/1/approve">Approve</a>'

    assert_equal expected_link, get_link(news, :approve)

    assert_raises TypeError do
      get_link(Opportunity, :approve)
    end
  end

  test 'get_link with reject' do
    news = FactoryBot.create(:opportunity, id: 1)
    expected_link = '<a class="btn btn-danger" title="Reject" rel="nofollow" data-method="put" href="/admin/opportunities/1/reject">Reject</a>'

    assert_equal expected_link, get_link(news, :reject)

    assert_raises TypeError do
      get_link(Opportunity, :reject)
    end
  end

  test 'get_link with custom action' do
    maintenance_debt = FactoryBot.create(:maintenance_debt, id: 1)

    assert_raises ArgumentError do
      get_link(maintenance_debt, :convert_to_staffing_debt)
    end

    expected_link = '<a class="btn btn-secondary" title="Convert To Staffing Debt" rel="nofollow" data-method="put" href="/admin/maintenance_debts/1/convert_to_staffing_debt">Convert To Staffing Debt</a>'

    assert_equal expected_link, get_link(maintenance_debt, :convert_to_staffing_debt, http_method: :put)
  end

  test 'get_link requires an object' do
    assert_raises ArgumentError do
      get_link(nil, :view)
    end
  end

  test 'get_link gives a warning when the object is of the wrong kind' do
    instance = FaultReport.new

    wrong_kind_hash = {
      index: instance,
      new: instance,
      show: instance.class,
      edit: instance.class,
      destroy: instance.class,
      answer: instance.class,
    }

    wrong_kind_hash.each do |action, object|
      assert_raises TypeError do
        get_link(object, action)
      end
    end
  end

  test 'get_link raises an ArgumentError when the action is not a GET action' do
    wrong_actions = [:create, :update, :delete]

    wrong_actions.each do |action|
      assert_raises ArgumentError do
        get_link(Admin::Proposals::Proposal, action)
      end
    end
  end

  test 'can overrule using condition' do
    @current_user = users(:user)

    news = FactoryBot.create(:news, id: 1, title: 'Vikings have taken over the Bedlam')

    assert_not @current_user.can?(:destroy, news)

    expected_link = '<a class="btn btn-danger" data-title="Deleting the News &quot;Vikings have taken over the Bedlam&quot;" data-confirm="Are you sure you want to delete the News &quot;Vikings have taken over the Bedlam&quot;?" title="Destroy" rel="nofollow" data-method="delete" href="/admin/news/1-vikings-have-taken-over-the-bedlam"><span class="no-wrap"><i class="fa fa-trash" aria-hidden=”true”></i> Destroy</span></a>'

    assert_equal expected_link, get_link(news, :destroy, condition: true)
  end

  test 'can specify additional condition' do
    news = FactoryBot.create(:news, id: 1, title: 'Vikings have taken over the Bedlam')

    assert@current_user.can?(:destroy, news)

    assert_nil get_link(news, :destroy, additional_condition: false)
  end

  test 'return link text when condition fails for show' do
    staffing = FactoryBot.create(:staffing, id: 1, show_title: 'The Wondrous Adventures of Finbar the Viking')

    assert_equal 'The Wondrous Adventures of Finbar the Viking', get_link(staffing, :show, condition: false)
    assert_nil get_link(staffing, :show, condition: false, return_link_text_if_no_permission: false)
  end

  test 'return link text when condition fails for other action' do
    staffing = FactoryBot.create(:staffing, id: 1)

    assert_nil get_link(staffing, :edit, condition: false)

    assert_equal '<span class="no-wrap"><i class="fa fa-pencil-alt" aria-hidden=”true”></i> Edit</span>', get_link(staffing, :edit, condition: false, return_link_text_if_no_permission: true)
  end

  test 'wrap_in_tags' do
    without_tags = 'Dennis the Donkey'
    with_tags = '<td>Dennis the Donkey</td>'.html_safe

    assert_equal with_tags, wrap_in_tags(without_tags, 'td')
  end

  test 'default generate_link_text for instances with name propery' do
    object = FactoryBot.build(:show, name: 'The Wondrous Adventures of Finbar the Viking')

    instance_hash = {
      show: 'The Wondrous Adventures of Finbar the Viking',
      edit: '<span class="no-wrap"><i class="fa fa-pencil-alt" aria-hidden=”true”></i> Edit</span>',
      destroy: '<span class="no-wrap"><i class="fa fa-trash" aria-hidden=”true”></i> Destroy</span>',
      answer: 'Answer'
    }

    instance_hash.each do |action, link_text|
      assert_equal link_text, generate_link_text(nil, object, action, nil, nil)
    end
  end

  test 'default generate_link_text for instances without name propery' do
    object = FactoryBot.build(:fault_report)

    instance_hash = {
      show: 'Show Fault Report',
      edit: '<span class="no-wrap"><i class="fa fa-pencil-alt" aria-hidden=”true”></i> Edit</span>',
      destroy: '<span class="no-wrap"><i class="fa fa-trash" aria-hidden=”true”></i> Destroy</span>',
      approve: 'Approve'
    }

    instance_hash.each do |action, link_text|
      assert_equal link_text, generate_link_text(nil, object, action, nil, nil)
    end
  end

  test 'default generate_link_text for classes' do
    object = Admin::MaintenanceDebt

    class_hash = {
      index: '<span class="no-wrap"><i class="fa fa-th-list" aria-hidden=”true”></i> Show All</span> Maintenance Debts',
      new: '<span class="no-wrap"><i class="fa fa-plus" aria-hidden=”true”></i> New</span> Maintenance Debt',
    }

    class_hash.each do |action, link_text|
      assert_equal link_text, generate_link_text(nil, object, action, nil, nil)
    end
  end

  test 'generate_link_text with link text already specified' do
    object = Admin::MaintenanceDebt

    link_text = 'There is not much to say'

    assert_equal link_text, generate_link_text(link_text, object, :show, nil, nil)

    assert_equal link_text, generate_link_text(link_text, object, :edit, 'Believe', true)
  end

  test 'generate_link_text with prefix specified' do
    object = Admin::MaintenanceDebt

    prefix = 'Do You Want To Clear'

    assert_equal 'Do You Want To Clear', generate_link_text(nil, object, :edit, prefix, nil)
    assert_equal 'Do You Want To Clear Maintenance Debt', generate_link_text(nil, object, :edit, prefix, true)

    # Also test that it works for the special case of show.
    assert_equal 'Do You Want To Clear', generate_link_text(nil, object, :show, prefix, nil)
  end

  test 'get_default_html_class' do
    hash = {
      show: '',
      new: 'btn btn-primary',
      destroy: 'btn btn-danger',
      edit: 'btn btn-secondary',
      index: 'btn btn-secondary',
      approve: 'btn btn-success',
      reject: 'btn btn-danger',
      answer: 'btn btn-secondary',
      hexagon: 'btn btn-secondary',
    }

    hash.each do |action, html_class|
      assert_equal html_class, get_default_html_class(action)
    end
  end

  test 'get_namespace_for_link for model not in admin namespace' do
    object = roles(:member)

    assert_nil get_namespace_for_link(object, false)

    assert_equal(:admin, get_namespace_for_link(object, true))
  end

  test 'get_namespace_for_link for model in admin namespace' do
    object = admin_questions(:questionnaire_template_question_one)

    # Should return nil because the admin is already included in the object name.

    assert_nil get_namespace_for_link(object, false)

    assert_nil get_namespace_for_link(object, true)
  end

  test 'get_default_http_method' do
    hash = {
      show: :get,
      index: :get,
      new: :get,
      edit: :get,
      destroy: :delete,
      approve: :put,
      reject: :put
    }

    hash.each do |action, http_method|
      assert_equal http_method, get_default_http_method(action)
    end

    assert_raises ArgumentError do
      get_default_http_method(:answer)
    end
  end

  test 'get_default_link_target' do
    skip 'Well this one is pesky. It is pretty much covered by the tests that get the whole link, but it would be nice if this worked'

    object = FactoryBot.create(:proposal)

    hash = {
      show: '',
      index: '',
      new: '',
      edit: '',
      destroy: '',
    }

    hash.each do |action, response|
      assert_equal '', get_default_link_target(object, action, nil, nil)
    end

    assert_raises ArgumentError do
      get_default_http_method(:answer)
    end
  end

  test 'raise ArgumentError during get_default_link_target for non-default action' do
    assert_raises ArgumentError do
      get_default_link_target(FaultReport, :towers, nil, nil)
    end
  end

  test 'get default_link_target with special arguments' do
    skip 'Well this one is pesky, for the same reason as the other one. There is something with url_for that doesn\t want to work. It is pretty much covered by the tests that get the whole link, but it would be nice if this worked'
  end

  test 'get_confirm_data' do
    object = FactoryBot.create(:staffing_debt)

    assert_nil get_confirm_data(object, :show, nil, nil, nil)

    confirm_hash = {
      title: 'Hexagon',
      confirm: nil,
      verify: 'Pineapple'
    }

    assert_equal confirm_hash, get_confirm_data(object, :edit, 'Hexagon', nil, 'Pineapple')
  end

  test 'get_confirm_data for destroy' do
    object = FactoryBot.create(:draft_mass_mail, subject: 'We are building a Hexagon again!')

    default_destroy_hash_for_object_with_subject = {
      title: 'Deleting the Mass Mail "We are building a Hexagon again!"',
      confirm: 'Are you sure you want to delete the Mass Mail "We are building a Hexagon again!"?',
      verify: nil
    }

    assert_equal default_destroy_hash_for_object_with_subject, get_confirm_data(object, :destroy, nil, nil, nil)

    object = FactoryBot.create(:staffing_debt)

    default_destroy_hash = {
      title: 'Deleting the Staffing Debt',
      confirm: 'Are you sure you want to delete the Staffing Debt?',
      verify: nil
    }

    assert_equal default_destroy_hash, get_confirm_data(object, :destroy, nil, nil, nil)

    overridden_destroy_hash = {
      title:'Deleting the Staffing Debt',
      confirm: 'Pineapple',
      verify: nil
    }
    assert_equal overridden_destroy_hash, get_confirm_data(object, :destroy, nil, 'Pineapple', nil)
  end
end
