// Converted from CoffeeSript using decaffeinate
// Bootstrap 5: Remove the jQuery bits and keep just the Bootstrap 5.
window.addEventListener('load', function() {
    addPreviewClickHandlersToButtonsIn(document);
});

// Looks for all preview navigation buttons that are descendants of the passed element and adds a click handler to them to generate the preview when clicked.
// It would be better to listen for the show.bs.tab event, but that event is not fired for some reason.
function addPreviewClickHandlersToButtonsIn(element) {
  const previewButtons = element.getElementsByClassName('preview-toggle');

  for (let button of previewButtons) {
    button.addEventListener('click', event => {
      generatePreview(event);
    });
  }
}

function generatePreview(event) {
  // Find the ID to differentiate between this md_editor and other ones for the preview and input fields based on the one set on the clicked button.
  const id = $(event.currentTarget).data("preview-id");
  const input = $("#input-field-" + id + " textarea");
  const preview = $("#preview-placeholder-" + id)

  // Set a loading text while we wait for the request to return.
  preview.html('<b>Please Wait. Loading Preview...</b>');

  var token = $('meta[name="csrf-token"]').attr('content');

  // Send a JSON request to the server to render the markdown. We need the CSRF token to be set in the headers.
  return $.ajax({
    type: 'POST',
    url: '/markdown/preview.json',
    data: JSON.stringify({ input_html: encodeURIComponent(input.val()) }),
    beforeSend: function (xhr) {
      xhr.setRequestHeader('X-CSRF-Token', token)
    },
    // If there's a success, render the markdown from the server.
    success(data) {
      preview.html(data.rendered_md);
    },
    // If there's an error, render the error message in the preview pane.
    error(jqXHR, textStatus, errorThrown) {
      const error_data = JSON.parse(jqXHR.responseText);
      const error_html =  `\
<b>There was an error rendering your kramdown.</b>
<pre>${error_data.error}</pre>\
`;
      return preview.html(error_html);
    },
    contentType: false,
    processData: false
  });
}

// After a new nested_fields item is inserted using cocoon, we need to add the preview click handlers to the new item.
$(document).on("cocoon:after-insert", function(e, insertedItem, originalEvent) {
  // If there is no markdown editor in the inserted item, we don't need to do anything.
  if (insertedItem[0].getElementsByClassName('md-editor').length === 0) {
    return;
  }

  // Get the ID of the markdown editor in the inserted item. This is the ID used in the above script, so we need to replace it, or the navigation and preview for separate editors will interfere with each other.
  const idToReplace = insertedItem[0].getElementsByClassName('md-editor')[0].getAttribute('md-editor-id');

  // Set the newId to the current time in milliseconds, so it is unique on the page.
  const newId = new Date().getTime();

  // Update all instances of the old id (which would otherwise be the same for all templates) with the new id.
  // This ID is different from the actual ID used by cocoon/nested fields. This ID is just used because we need
  // to anchor to specific elements for the tabbing and preview, and the nestd field ID only applies to inputs.
  insertedItem[0].innerHTML = insertedItem[0].innerHTML.replace(new RegExp(idToReplace, 'g'), newId);
  addPreviewClickHandlersToButtonsIn(insertedItem[0]);
});
