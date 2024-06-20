// This script initialises the select2 fields on the website based on attributes defined in the HTML.

// Add select2 fields to fields that exist on document load.
document.addEventListener('DOMContentLoaded', function() {
  // Initialise all select2 fields that exist on document start.
  activateSelect2Fields(document);
});

// Initialise all select2 fields that are added dynamically using cocoon.
$(document).on("cocoon:after-insert", function(e, insertedItem, originalEvent) {
  activateSelect2Fields(insertedItem[0]);
});

function activateSelect2Fields(parentElement) {
  // Find all select2 fields that are children of the parent.
  const select2Fields = parentElement.querySelectorAll('.simple-select2');
  for (let i = 0; i < select2Fields.length; i++) {
    const el = select2Fields[i];
    // Set the width to 100% for select2 fields so they do not shrink unreasonably.
    // I am not sure how to best allow this to be overridden. Maybe an attr, or just put a div around the select2 that you resize.
    var attributes = {
      theme: 'bootstrap4', 
      width: '100%',
      allowClear: $(el).data('allow-clear') || true,
      placeholder: $(el).data('placeholder') || 'Select an option...',
    };

    // If there is a select2-with-tags attr (allowing custom input), set tags enabled in the select2 attributes.
    if (el.getAttribute('select2-with-tags') === 'true') {
      attributes['tags'] = true;
      attributes['placeholder'] = "Select option or enter custom value...";
    }

    // If there is a remote-source specified, set up this select2 element for ajax.
    if ($(el).data('remote-source')) {
      const ajax_attributes = {
        url: $(el).data('remote-source'),
        dataType: 'json',
        delay: 250,
        data: function(params) {
          var query = {
            page: params.page || 1,
            _type: params._type || 'query'
          };

          query[$(el).data('query-field')] = params.term;

          // For user search fields.
          // Query parameters will be ?q[full_name_cont]=[term]&all_users=
          if ($(el).data('show-non-members')) {
            query['show_non_members'] = $(el).data('show-non-members');
          }
  
          return query;
        }
      };

      attributes['ajax'] = ajax_attributes;
    }
  
    // Finally, instantiate the select2 field with the attributes determined above.
    // This needs to be jQuery as select2 is a jQuery plugin.
    $(el).select2(attributes);
  };
}

document.addEventListener('select2:open', () => {
  document.querySelector('.select2-search__field').focus();
});