function loadTemplate() {
  var templateName = $('#template_list').val();
  
  $.getJSON(
    '/staffing_templates/' + templateName + '.json',
    function (data) {
      
    }
  );
}

$(function () {
  $.getJSON(
    '/staffing_templates/templates.json',
    function (data) {
      $.each(data.templates, function (index, template) {
        $('#template_list').append('<option>' + template.name + '</option>');
      });
    }
  );
  
  $('#template_list').change(loadTemplate);
});