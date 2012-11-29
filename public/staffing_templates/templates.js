(function () {
  "use strict";
    
  var selected_template = null;

  function loadTemplate() {
    //TODO: This feels dirty - there must be a better way:
    $.each(selected_template.jobs, function (index, job) {      
      var setValue = function (e) {
        e.field.find('[name$="[name]"]').val(job);
      };
      
      $(document).one('nested:fieldAdded', setValue);
      $('a[data-association="staffing_jobs"].add_nested_fields').click();
    });
    
    $('#template_modal').modal('hide');
  }

  function getTemplate() {
    var templateName = $('#template_list').val();
    
    $('#template_load').off('click', loadTemplate);
    
    if (templateName === "") {
      $('#template_summary').empty();
      selected_template = null;
      
      $('#template_load').addClass('disabled');
      return;
    }
    
    $.getJSON(
      '/staffing_templates/' + templateName + '.json',
      function (data) {
        selected_template = data;
        $('#template_summary').empty();
        
        $('#template_summary').append('<h3>Jobs</h3>');
        var jobs_list = $('<ul id="template_jobs_list"></ul>');
        $.each(data.jobs, function (index, job) {
          $(jobs_list).append('<li>' + job + '</li>');
        });
        $('#template_summary').append(jobs_list);
        
        $('#template_load').on('click', loadTemplate);
        $('#template_load').removeClass('disabled');
      }
    );
  }

  $(function () {
    $.getJSON(
      '/staffing_templates/templates.json',
      function (data) {
        $.each(data.templates, function (index, template) {
          $('#template_list').append('<option value="' + index + '">' + template.name + '</option>');
        });
      }
    );
    
    $('#template_list').change(getTemplate);
  });
}());