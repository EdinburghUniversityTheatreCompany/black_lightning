require 'test_helper'

class Admin::Questionnaires::QuestionnairesControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @questionnaire = FactoryBot.create(:questionnaire)
  end

  test 'should get index' do
    FactoryBot.create_list(:questionnaire, 3)

    get :index
    assert_response :success
    assert_not_nil assigns(:questionnaires)
  end

  test 'should get index with many records' do
    FactoryBot.create_list(:questionnaire, 15)

    get :index
    assert_response :success
    assert_not_nil assigns(:questionnaires)
  end

  test 'should show admin_questionnaires_questionnaire' do
    get :show, params: { id: @questionnaire }
    assert_response :success
  end

  test 'should get edit' do
    get :edit, params: { id: @questionnaire }
    assert_response :success
  end

  test 'should get new' do
    FactoryBot.create(:show, start_date: Date.today.advance(days: 5))
    get :new
    assert_response :success
  end

  test 'should get new with show' do
    show = FactoryBot.create(:show, start_date: Date.today.advance(days: 5))
    get :new, params: { show_id: show.id }
    assert_response :success
  end

  test 'should not get new when there are no future shows' do
    Show.all.destroy_all
    get :new
    assert_redirected_to admin_questionnaires_questionnaires_path
  end

  test 'should create' do
    attributes = {
      show_id: @questionnaire.show_id,
      name: 'Finbar the Viking'
    }

    assert_difference('Admin::Questionnaires::Questionnaire.count') do
      post :create, params: { admin_questionnaires_questionnaire: attributes }
    end

    assert Admin::Questionnaires::Questionnaire.where(name: attributes[:name], show_id: attributes[:show_id])

    # Assert create cannot add any answers.
    assert(assigns(:questionnaire).answers.none? { |answer| answer.answer == 'Hexagon' })

    assert_redirected_to admin_questionnaires_questionnaire_path(assigns(:questionnaire))
  end

  test 'should not create invalid questionnaire' do
    attributes = {
      show_id: nil,
      name: 'Finbar the Viking'
    }

    assert_no_difference('Admin::Questionnaires::Questionnaire.count') do
      post :create, params: { admin_questionnaires_questionnaire: attributes }
    end

    assert_response :unprocessable_entity
  end

  test 'should update admin_questionnaires_questionnaire' do
    attributes = get_attributes

    put :update, params: { id: @questionnaire, admin_questionnaires_questionnaire: attributes }

    assert(assigns(:questionnaire).questions.any? { |question| question.response_type == 'Testing' })
    assert_equal 'Finbar the Viking', assigns(:questionnaire).name

    # Test that update cannot change the show or add any answers.
    assert assigns(:questionnaire).show_id = @questionnaire.show_id
    assert(assigns(:questionnaire).answers.none? { |answer| answer.answer == 'Hexagon' })

    assert_redirected_to admin_questionnaires_questionnaire_path(@questionnaire)
  end

  test 'should not update invalid admin_questionnaires_questionnaire' do
    attributes = { name: nil }

    put :update, params: { id: @questionnaire, admin_questionnaires_questionnaire: attributes }

    assert_response :unprocessable_entity
  end

  test 'should get answer' do
    get :answer, params: { id: @questionnaire }
    assert_response :success
  end

  test 'should get answer when there is an answer with a question id that is no longer on the questionnaire' do
    @questionnaire.answers << FactoryBot.create(:answer, question_id: 0)
    get :answer, params: { id: @questionnaire }
    assert_response :success
  end

  test 'should submit answer' do
    attributes = get_attributes

    put :set_answers, params: { id: @questionnaire, admin_questionnaires_questionnaire: attributes }

    assert(assigns(:questionnaire).answers.any? { |answer| answer.answer == 'Hexagon' })

    # Test that answer cannot change the show, the name, and the questions.
    assert assigns(:questionnaire).show_id = @questionnaire.show_id
    assert_equal @questionnaire.name, assigns(:questionnaire).name
    assert(assigns(:questionnaire).questions.none? { |aquestion| aquestion.response_type == 'Testing' })

    assert_redirected_to admin_questionnaires_questionnaire_path(@questionnaire)
  end

  test 'should not submit invalid answer' do
    attributes = {
      answers_attributes: { '0' => { question_id: nil, answer: 'Testing' } }
    }

    put :set_answers, params: { id: @questionnaire, admin_questionnaires_questionnaire: attributes }

    assert_response :unprocessable_entity
  end

  test 'should destroy admin_questionnaires_questionnaire' do
    assert_difference('Admin::Questionnaires::Questionnaire.count', -1) do
      delete :destroy, params: { id: @questionnaire }
    end

    assert_redirected_to admin_questionnaires_questionnaires_path
  end

  private

  def get_attributes
    return {
      show_id: 0,
      name: 'Finbar the Viking',
      answers_attributes: { '0' => { answer: 'Hexagon', question_id: @questionnaire.questions.first.id } },
      questions_attributes: {
        '0' => { question_text: 'Testing', response_type: 'Testing' }
      }
    }
  end
end
