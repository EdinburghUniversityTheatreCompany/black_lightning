// Call Templates
(function () {
  "use strict";

  var selected_template = null;

  function loadTemplate() {
    //TODO: This feels dirty - there must be a better way:
    $.each(selected_template.questions, function (index, question) {
      var setValue = function (e) {
        e.field.find('[name$="[question_text]"]').val(question.question_text);
        e.field.find('[name$="[response_type]"]').val(question.response_type);
      };

      $(document).one('nested:fieldAdded', setValue);
      $('a[data-association="questions"].add_nested_fields').click();
    });

    $('#template_modal').modal('hide');
  }

  function getTemplate() {
    var template_id = $('#template_list').val();

    $('#template_load').off('click', loadTemplate);

    if (template_id === "") {
      $('#template_summary').empty();
      selected_template = null;

      $('#template_load').addClass('disabled');
      return;
    }

    $.getJSON(
      '/admin/questionnaires/questionnaire_templates/' + template_id + '.json',
      function (data) {
        selected_template = data;
        $('#template_summary').empty();

        $('#template_summary').append('<h3>Questions</h3>');
        var jobs_list = $('<ul id="template_jobs_list"></ul>');
        $.each(data.questions, function (index, question) {
          $(jobs_list).append('<li><p>' + question.question_text + '</p></li>');
        });
        $('#template_summary').append(jobs_list);

        $('#template_load').on('click', loadTemplate);
        $('#template_load').removeClass('disabled');
      }
    );
  }

  $(function () {
    $.getJSON(
      '/admin/questionnaires/questionnaire_templates.json',
      function (data) {
        $.each(data, function (index, template) {
          $('#template_list').append('<option value="' + template.id + '">' + template.name + '</option>');
        });
      }
    );

    $('#template_list').change(getTemplate);
  });
}());