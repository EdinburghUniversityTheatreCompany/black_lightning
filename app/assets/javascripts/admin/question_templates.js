// Execute the script after the DOM is fully loaded
document.addEventListener('DOMContentLoaded', () => {
  new TemplateLoader();
});

// Constants for item types to avoid typos and improve readability
const ITEMS_TYPE = {
  QUESTIONS: 'questions',
  JOBS: 'jobs'
};

class TemplateLoader {
  constructor() {
    // Get base URL and items type from meta tags in the HTML
    // You need to set a meta tag with the templates base url and the items_type.
    // Do not end the url with a slash.
    // See questionnaires form for an example on how to do this.
    // Make sure you set the meta tag ABOVE the javascript include tag  
    this.templatesBaseUrl = $('meta[name="templates-base-url"]').attr("content");
    this.itemsType = $('meta[name="templates-items-type"]').attr("content");
    this.templateItem = null; // Holds the current item being added from the template
    this.globalData = null;  // Stores all data for the selected template
    this.allTemplates = []; // New property to store all templates

    this.validateSetup();
    this.initEventListeners();
  }

  // Validate that required meta tags are set correctly
  validateSetup() {
    if (!this.templatesBaseUrl) {
      alert("'templates_base_url' is null. Is it set properly?");
    }

    // if the templatesBaseUrl does not end in '.json', add '.json' to the end.
    if (!this.templatesBaseUrl.endsWith('.json')) {
      this.templatesBaseUrl += '.json';
    }

    if (!this.itemsType || ![ITEMS_TYPE.QUESTIONS, ITEMS_TYPE.JOBS].includes(this.itemsType)) {
      alert("'items_type' is null or not 'questions' or 'jobs'. Is it set properly?");
    }
  }

  // Initialize all event listeners
  initEventListeners() {
    // Listen for Cocoon's after-insert event to populate new fields
    $(document).on('cocoon:after-insert', this.handleCocoonInsert.bind(this));

    // Listen for changes in the template dropdown to load template data
    $('#template_list').on('change', this.getTemplate.bind(this));

    // Load the initial list of available templates
    this.loadTemplateList();
  }

  // Handle Cocoon's after-insert event to populate the new fields with template data
  handleCocoonInsert(e, insertedItem) {
    if (!this.templateItem) return;

    // If the type is questions, the added item can either be a question or a notify email.
    if (this.itemsType === ITEMS_TYPE.QUESTIONS) {
      if (insertedItem.hasClass('question')) {
        // Populate question text and response type for questions
        insertedItem.find('[name$="[question_text]"]').val(this.templateItem.question_text);
        insertedItem.find('[name$="[response_type]"]').val(this.templateItem.response_type);
      } else if (insertedItem.hasClass('email')) {
        // Populate email for notify emails
        insertedItem.find('[name$="[email]"]').val(this.templateItem.email);
      }
    } else if (this.itemsType === ITEMS_TYPE.JOBS) {
      // Populate job name for staffing jobs
      insertedItem.find('[name$="[name]"]').val(this.templateItem.name);
    }
  }

  // Trigger the loading of template items when the "Load" button is clicked
  loadTemplate() {
    if (this.itemsType === ITEMS_TYPE.QUESTIONS) {
      // For questions, load both questions and notify emails
      this.loadTemplateHelper('question_add_button', this.globalData.questions);
      this.loadTemplateHelper('notify_email_add_button', this.globalData.notify_emails);
    } else if (this.itemsType === ITEMS_TYPE.JOBS) {
      // For jobs, load staffing jobs
      this.loadTemplateHelper('staffing_job_add_button', this.globalData.staffing_jobs);
    }
  }

  // Helper method to load template items by triggering Cocoon's add button
  loadTemplateHelper(addFieldsButtonClass, templateItems) {
    templateItems.forEach(item => {
      this.templateItem = item;
      // This loops over every item in the template and clicks the corresponding 'add fields' button.
      // This then triggers the cocoon:after-insert event (see above) which will insert the data into the fields.
      $('.' + addFieldsButtonClass).first().trigger('click');
    });

    // After adding all the items, set the item back to null so adding a new field will add an empty field rather than the data from the last item in the template.
    this.templateItem = null;
  }

  // Fetch the data for the template when a template is selected from the dropdown
  getTemplate() {
    const templateId = $('#template_list').val();
    $('#template_load').off('click', this.loadTemplate.bind(this));

    if (templateId === "") {
      // If no template is selected, clear the summary and disable the load button
      $('#template_summary').empty();
      this.globalData = null;
      $('#template_load').addClass('disabled');
      return;
    }

    // Find the selected template from the allTemplates array
    const selectedTemplate = this.allTemplates.find(template => template.id == templateId);

    if (selectedTemplate) {
      this.globalData = selectedTemplate;
      this.updateTemplateSummary();
      // Enable the load button and bind the loadTemplate method
      $('#template_load').on('click', this.loadTemplate.bind(this));
      $('#template_load').removeClass('disabled');
    } else {
      console.error('Selected template not found in the loaded templates: ' + templateId);
      $('#template_summary').empty().append('<p>Error: Template not found</p>');
      $('#template_load').addClass('disabled');
    }
  }

  // Update the template summary list in the modal
  updateTemplateSummary() {
    // Extract item names or question texts based on the item type
    const templateItems = this.itemsType === ITEMS_TYPE.QUESTIONS
      ? this.globalData.questions.map(question => question.question_text)
      : this.globalData.staffing_jobs.map(job => job.name);

    // Clear the old summary and add the new items
    $('#template_summary').empty().append('<h3>Items</h3>');
    const itemsList = $('<ul id="template_items_list"></ul>');
    templateItems.forEach(itemValue => {
      $(itemsList).append(`<li>${itemValue}</li>`);
    });
    $('#template_summary').append(itemsList);
  }

  // Load the list of available templates into the dropdown
  loadTemplateList() {
    $.getJSON(this.templatesBaseUrl)
      .done(data => {
        if (Array.isArray(data) && data.length > 0) {
          this.allTemplates = data; // Store all templates
          data.forEach(template => {
            $('#template_list').append(`<option value="${template.id}">${template.name}</option>`);
          });
        } else {
          console.log('Data is empty or not an array');
        }
      })
      .fail((jqXHR, textStatus, errorThrown) => {
        console.error('AJAX request failed:', textStatus, errorThrown);
      });
  }
}