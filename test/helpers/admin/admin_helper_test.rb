require 'test_helper'

  ##
  # This does not test conditions, because there is no ability present during testing.
  # You can, however, see that the condition bit works.
  # If you ever find a solution to this, remember that you can give the committee role
  # permission to destroy mass mails and maintenance debts and sign_in as committee.
  ##
class Admin::AdminHelperTest < ActionView::TestCase
  include NameHelper
  include ApplicationHelper

  test 'Can destroy_with_flash_message' do
    # Maintenance debt does not have a name, title, subject, or anything like that, so we can test if it defaults to class name.
    @maintenance_debt = FactoryBot.create(:maintenance_debt)
    destroy_with_flash_message(@maintenance_debt, condition: true)

    assert_equal ['The Maintenance Debt has been successfully destroyed.'], flash[:success]
    assert_nil flash[:error]
  end

  test 'Can destroy_with_flash_message with name' do
    @mass_mail = FactoryBot.create(:draft_mass_mail)

    destroy_with_flash_message(@mass_mail, name: 'The All-Mighty Hexagon', condition: true)

    assert_equal ['The All-Mighty Hexagon has been successfully destroyed.'], flash[:success]
  end

  test 'Can destroy_with_flash_message with custom success message' do
    @mass_mail = FactoryBot.create(:draft_mass_mail)

    destroy_with_flash_message(@mass_mail, condition: true, success_message: 'Finbar the Viking is Watching')

    assert_equal ['Finbar the Viking is Watching'], flash[:success]
  end

  test 'Cannot destroy_with_flash_message for nil' do
    assert_raise ArgumentError do
      destroy_with_flash_message(nil, condition: true)
    end
  end

  test 'Cannot destroy_with_flash_message for a class' do
    assert_raise TypeError do
      destroy_with_flash_message(MassMail, condition: true)
    end
  end

  test 'destroy_with_flash_message for invalid object adds errors to flash' do
    @mass_mail = FactoryBot.create(:sent_mass_mail)

    assert_not destroy_with_flash_message(@mass_mail, condition: true)

    assert_equal(["The Mass Mail \"#{@mass_mail.subject}\" could not be destroyed."] + @mass_mail.errors.messages[:destroy], flash[:error])
    assert_nil flash[:success]
  end

  test 'destroy_with_flash_message for object with restrict_with_error does not destroy the object' do
    @proposal = FactoryBot.create(:proposal)

    assert_no_difference 'Admin::Proposals::Proposal.count' do
      assert_not destroy_with_flash_message(@proposal, condition: true)

      assert_equal ["The Proposal \"#{@proposal.show_title}\" could not be destroyed."] + @proposal.errors.messages[:destroy], flash[:error]
    end
  end

  test 'destroy_with_flash_message! for invalid object raises an error' do
    @mass_mail = FactoryBot.create(:sent_mass_mail)

    assert_raise ActiveRecord::RecordNotDestroyed do
      destroy_with_flash_message!(@mass_mail, condition: true)
    end

    assert_equal(["The Mass Mail \"#{@mass_mail.subject}\" could not be destroyed.", *@mass_mail.errors.messages[:destroy]], flash[:error])
    assert_nil flash[:success]
  end

  test 'destroy_with_flash_message for invalid object adds a custom error' do
    @mass_mail = FactoryBot.create(:sent_mass_mail)

    assert_not destroy_with_flash_message(@mass_mail, condition: true, error_message: 'Hexagons Forever')
    assert_equal(['Hexagons Forever', *@mass_mail.errors.messages[:destroy]], flash[:error])
  end

  test 'destroy_with_flash_message for invalid object adds a custom error without errors appended' do
    @mass_mail = FactoryBot.create(:sent_mass_mail)

    assert_not destroy_with_flash_message(@mass_mail, condition: true, error_message: 'Hexagons Forever', append_errors_to_error_flash: false)

    assert_equal(['Hexagons Forever'], flash[:error])
  end
end
