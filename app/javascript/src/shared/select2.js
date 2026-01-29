// This script initialises the select2 fields on the website based on attributes defined in the HTML.

// Shared cache for all Select2 AJAX requests on this page.
// Cache is automatically cleared on page navigation (appropriate for user data).
const select2Cache = {
  data: {},
  timestamps: {},
  maxAge: 60000, // Cache entries expire after 60 seconds

  generateKey(url, params) {
    const sortedParams = Object.keys(params)
      .sort()
      .map(k => `${k}=${params[k]}`)
      .join('&');
    return `${url}?${sortedParams}`;
  },

  get(key) {
    const timestamp = this.timestamps[key];
    if (timestamp && (Date.now() - timestamp) < this.maxAge) {
      return this.data[key];
    }
    delete this.data[key];
    delete this.timestamps[key];
    return null;
  },

  set(key, value) {
    this.data[key] = value;
    this.timestamps[key] = Date.now();
  }
};

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
      const remoteUrl = $(el).data('remote-source');
      const queryField = $(el).data('query-field');
      const showNonMembers = $(el).data('show-non-members');

      const ajax_attributes = {
        url: remoteUrl,
        dataType: 'json',
        delay: 250,
        data: function(params) {
          var query = {
            page: params.page || 1,
            _type: params._type || 'query'
          };

          query[queryField] = params.term;

          // For user search fields.
          // Query parameters will be ?q[full_name_cont]=[term]&all_users=
          if (showNonMembers) {
            query['show_non_members'] = showNonMembers;
          }

          return query;
        },
        transport: function(params, success, failure) {
          const cacheKey = select2Cache.generateKey(params.url, params.data);
          const cachedData = select2Cache.get(cacheKey);

          if (cachedData) {
            // Return cached data asynchronously to match AJAX behavior
            setTimeout(function() { success(cachedData); }, 0);
            return { abort: function() {} };
          }

          // Not in cache, make the actual AJAX request
          return $.ajax(params)
            .done(function(data) {
              select2Cache.set(cacheKey, data);
              success(data);
            })
            .fail(failure);
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