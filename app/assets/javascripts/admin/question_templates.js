// Very similar to assets/javascripts/admin/staffing_templates.

(function () {
  "use strict";

  var selected_template = null;

  // You need to set a meta tag with the templates base url.
  // Do not end with a slash.
  // See questionnaires form for an example on how to do this.
  // Make sure you set the meta tag ABOVE the javascript include tag
  var templates_base_url = $('meta[name="templates-base-url"]').attr("content");

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
      templates_base_url + '/' + template_id + '.json',
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
      templates_base_url,
      function (data) {
        $.each(data, function (index, template) {
          $('#template_list').append('<option value="' + template.id + '">' + template.name + '</option>');
        });
      }
    );

    $('#template_list').change(getTemplate);
  });
}());