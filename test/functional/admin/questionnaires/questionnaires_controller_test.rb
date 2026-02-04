require "test_helper"

class Admin::Questionnaires::QuestionnairesControllerTest < ActionController::TestCase
  include AcademicYearHelper

  setup do
    @admin = users(:admin)
    sign_in @admin

    @questionnaire = FactoryBot.create(:questionnaire)
  end

  test "should get index" do
    get_index_process
  end

  test "should get index on Christmas" do
    # Christmas is an edge case where the terms swap over. It should still work on this day.
    travel_to Time.zone.local(2021, 12, 25)

    assert Date.current, end_of_term

    get_index_process

    travel_back
  end

  test "should get index as normal user" do
    show = FactoryBot.create(:show, start_date: Date.current, end_date: Date.current, team_member_count: 1)
    user = show.users.first

    assert_not_nil user

    sign_out @admin
    sign_in user

    questionnaires = FactoryBot.create_list(:questionnaire, 4, event: show)

    get :index
    assert_response :success
    assert_not_nil assigns(:questionnaires)

    questionnaire_ids = assigns(:questionnaires).values.flatten.collect(&:id).sort

    assert_equal questionnaires.collect(&:id).sort, questionnaire_ids
  end

  test "should show admin_questionnaires_questionnaire" do
    get :show, params: { id: @questionnaire }
    assert_response :success
  end

  test "should get edit" do
    get :edit, params: { id: @questionnaire }
    assert_response :success
  end

  test "should get new" do
    FactoryBot.create(:show, start_date: Date.current.advance(days: 5))
    get :new
    assert_response :success
  end

  test "should get new with show" do
    show = FactoryBot.create(:show, start_date: Date.current.advance(days: 5))
    get :new, params: { show_id: show.id }
    assert_response :success
  end

  test "should not get new when there are no future shows" do
    Event.all.delete_all

    assert Event.all.empty?

    get :new
    assert_redirected_to admin_questionnaires_questionnaires_path
  end

  test "should create" do
    attributes = {
      event_id: @questionnaire.event_id,
      name: "Finbar the Viking",
      notify_emails_attributes: { "0" => { email: "alice@testest.test" }, "1" => { email: "bob@test.test" } }
    }

    assert_difference("Admin::Questionnaires::Questionnaire.count") do
      post :create, params: { admin_questionnaires_questionnaire: attributes }
    end

    questionnaire = Admin::Questionnaires::Questionnaire.where(name: attributes[:name], event_id: attributes[:event_id]).first
    assert questionnaire.present?, "questionnaire was not found after creating."

    assert_redirected_to admin_questionnaires_questionnaire_path(assigns(:questionnaire))

    assert_equal 2, questionnaire.notify_emails.count, "Did not attach two notify emails"
    # Assert create cannot add any answers.
    assert(assigns(:questionnaire).answers.none? { |answer| answer.answer == "Hexagon" })
  end

  test "should not create invalid questionnaire" do
    attributes = {
      show_id: nil,
      name: "Finbar the Viking"
    }

    assert_no_difference("Admin::Questionnaires::Questionnaire.count") do
      post :create, params: { admin_questionnaires_questionnaire: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should update admin_questionnaires_questionnaire" do
    attributes = get_attributes

    put :update, params: { id: @questionnaire, admin_questionnaires_questionnaire: attributes }

    assert(assigns(:questionnaire).questions.any? { |question| question.response_type == "Testing" })
    assert_equal "Finbar the Viking", assigns(:questionnaire).name

    # Test that update cannot change the show or add any answers.
    assert_equal @questionnaire.event_id, assigns(:questionnaire).event_id
    assert(assigns(:questionnaire).answers.none? { |answer| answer.answer == "Hexagon" })

    assert_redirected_to admin_questionnaires_questionnaire_path(@questionnaire)
  end

  test "should not update invalid admin_questionnaires_questionnaire" do
    attributes = { name: nil }

    put :update, params: { id: @questionnaire, admin_questionnaires_questionnaire: attributes }

    assert_response :unprocessable_entity
  end

  test "should get answer" do
    get :answer, params: { id: @questionnaire }
    assert_response :success
  end

  test "should get answer when there is an answer with a question id that is no longer on the questionnaire" do
    question = @questionnaire.questions.sample

    new_answer = FactoryBot.create(:answer, question: question, answerable: @questionnaire)
    @questionnaire.answers << new_answer

    @questionnaire.questions.delete(question)

    get :answer, params: { id: @questionnaire }
    assert_response :success
  end

  test "should submit answer" do
    attributes = get_attributes

    put :set_answers, params: { id: @questionnaire, admin_questionnaires_questionnaire: attributes }

    assert(assigns(:questionnaire).answers.any? { |answer| answer.answer == "Hexagon" })

    # Test that answer cannot change the show, the name, and the questions.
    assert_equal @questionnaire.event_id, assigns(:questionnaire).event_id
    assert_equal @questionnaire.name, assigns(:questionnaire).name
    assert(assigns(:questionnaire).questions.none? { |aquestion| aquestion.response_type == "Testing" })

    assert_redirected_to admin_questionnaires_questionnaire_path(@questionnaire)
  end

  test "should submit answer does not send emails without notify specified" do
    attributes = get_attributes

    assert_no_difference "ActionMailer::Base.deliveries.count" do
      perform_enqueued_jobs do
        put :set_answers, params: { id: @questionnaire, admin_questionnaires_questionnaire: attributes }

        assert_redirected_to admin_questionnaires_questionnaire_path(@questionnaire)
      end
    end
  end

  test "should submit answer does send emails when notify is specified" do
    assert @questionnaire.notify_emails.count > 0, "The questionnaire has no notify emails. Specify some."

    attributes = get_attributes

    assert_difference "ActionMailer::Base.deliveries.count", 2 do
      perform_enqueued_jobs do
        put :set_answers, params: { id: @questionnaire, notify: "1", admin_questionnaires_questionnaire: attributes }

        assert_redirected_to admin_questionnaires_questionnaire_path(@questionnaire)
      end
    end
  end

  test "should not submit invalid answer" do
    attributes = {
      answers_attributes: { "0" => { question_id: nil, answer: "Testing" } }
    }

    put :set_answers, params: { id: @questionnaire, admin_questionnaires_questionnaire: attributes }

    assert_response :unprocessable_entity
  end

  test "should destroy admin_questionnaires_questionnaire" do
    assert_difference("Admin::Questionnaires::Questionnaire.count", -1) do
      delete :destroy, params: { id: @questionnaire }
    end

    assert_redirected_to admin_questionnaires_questionnaires_path
  end

  private

  def get_index_process
    old_show = FactoryBot.create(:show, start_date: Date.current.advance(years: -2), end_date: Date.current.advance(years: -2))
    previous_year = FactoryBot.create(:questionnaire, event: old_show)

    new_show = FactoryBot.create(:show, start_date: Date.current, end_date: Date.current)
    this_year = FactoryBot.create(:questionnaire, event: new_show)

    get :index

    assert_response :success
    assert_not_nil assigns(:questionnaires)

    assert_match "By default, this display only includes questionnaires for events taking place during the current semester", response.body

    questionnaire_ids = assigns(:questionnaires).values.flatten.collect(&:id)

    assert_includes questionnaire_ids, this_year.id
    assert_not_includes questionnaire_ids, previous_year.id
  end

  def get_attributes
    {
      show_id: 0,
      name: "Finbar the Viking",
      answers_attributes: { "0" => { answer: "Hexagon", question_id: @questionnaire.questions.first.id } },
      questions_attributes: { "0" => { question_text: "Testing", response_type: "Testing" },
      notify_emails_attributes: { "0" => { email: "alice@test.test" }, "1" => { email: "bob@test.test" } }
      }
    }
  end
end
