// I feel like having this global is not the neatest way of doing it, but I cannot think of another way.
// This stores the current item from the template that should be added.
var template_item = null;
// The type of the items. Either questions or jobs.
var items_type = null;
// Store all data for the question_template or staffing_jobs template to be loaded.
var global_data = null;

(function () {
  "use strict";

  // You need to set a meta tag with the templates base url and the items_type.
  // Do not end the url with a slash.
  // See questionnaires form for an example on how to do this.
  // Make sure you set the meta tag ABOVE the javascript include tag
  var templates_base_url = $('meta[name="templates-base-url"]').attr("content");
  items_type = $('meta[name="templates-items-type"]').attr("content");

  if(templates_base_url == null) {alert("'templates_base_url' is null. Is it set properly?")};
  if(items_type == null || (items_type != 'questions' && items_type != 'jobs')) {alert("'items_type' is null or not 'questions' or 'jobs'. Is it set properly?")};

  $(document)
    // This is the bit where the actual data is inserted.
    .on('cocoon:after-insert', function(e, insertedItem, originalEvent) {
      if (template_item === null) { return; }
  
      // If the type is questions, the added item can either be a question or a notify email.
      if(items_type == 'questions')
      {
        if(insertedItem.hasClass('question'))
        {
          insertedItem.find('[name$="[question_text]"]').val(template_item.question_text);
          insertedItem.find('[name$="[response_type]"]').val(template_item.response_type);
        }
        else if (insertedItem.hasClass('email'))
        {
          insertedItem.find('[name$="[email]"]').val(template_item.email)
        }
      }
      else if(items_type == 'jobs')
      {
        insertedItem.find('[name$="[name]"]').val(template_item.name);
      }
    })

  // Start inserting the fields
  function loadTemplate() {
    console.log('loadTemplate')
    if(items_type == 'questions')
    {
      loadTemplateHelper('question_add_button', global_data.questions);
      loadTemplateHelper('notify_email_add_button', global_data.notify_emails);
    }
    else if(items_type == 'jobs')
    {
      loadTemplateHelper('staffing_job_add_button', global_data.staffing_jobs);
    }
  }

  function loadTemplateHelper(add_fields_button_class, template_items)
  {
    // TODO: This feels dirty - there must be a better way.
    // This loops over every item in the template and clicks the corresponding 'add fields' button.
    // This then triggers the cocoon:after-insert event (see above) which will insert the data into the fields.
    $.each(template_items, function (index, item) {
      template_item = item;
      console.log('triggering click on ' + add_fields_button_class);
      console.log($('.' + add_fields_button_class).first());
      $('.' + add_fields_button_class).first().trigger('click');
      console.log('after click')
    });

    // After adding all the items, set the item back to null so adding a new field will add an empty field rather than the data from the last item in the template.
    template_item = null;
  }

  function getTemplate() {
    var template_id = $('#template_list').val();

    $('#template_load').off('click', loadTemplate);

    // If selecting blank, reset the current data to null.
    if (template_id === "") {
      $('#template_summary').empty();
      global_data = null;

      $('#template_load').addClass('disabled');
      return;
    }
    $.getJSON(
      templates_base_url + '/' + template_id + '.json',
      function (data) {
        global_data = data;

        // Load the items that will be previewed in the modal when selecting a template.
        var template_items = null;

        if (items_type == 'questions')
        {
          template_items = data.questions.map(question => question.question_text);
        }
        else if(items_type == 'jobs')
        {
          template_items = data.staffing_jobs.map(job => job.name);
        }

        // Clear the old summary, readd the header, and add all the current preview items.
        $('#template_summary').empty();

        $('#template_summary').append('<h3>Items</h3>');

        var items_list = $('<ul id="template_items_list"></ul>');

        $.each(template_items, function (index, item_value) {
          $(items_list).append('<li>' + item_value + '</li>');
        });

        $('#template_summary').append(items_list);

        // Enable the load button after the data has been loaded.
        $('#template_load').on('click', loadTemplate);
        $('#template_load').removeClass('disabled');
      }
    );
  }

  // After loading the document, load the template list.
  $(function () {
    $.getJSON(
      templates_base_url,
      function (data) {
        $.each(data, function (index, template) {
          $('#template_list').append('<option value="' + template.id + '">' + template.name + '</option>');
        });
      }
    );

    $('#template_list').on('change', getTemplate);
  });
}());
