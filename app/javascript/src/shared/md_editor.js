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

// Watch for dynamically inserted nested form rows and reinitialise any markdown editors inside them.
// Uses MutationObserver instead of the removed cocoon:after-insert jQuery event.
new MutationObserver((mutations) => {
  for (const mutation of mutations) {
    for (const node of mutation.addedNodes) {
      if (node.nodeType !== Node.ELEMENT_NODE) continue
      const editors = node.querySelectorAll?.(".md-editor")
      if (!editors?.length) continue

      const idToReplace = editors[0].getAttribute("md-editor-id")
      const newId = new Date().getTime()
      node.innerHTML = node.innerHTML.replace(new RegExp(idToReplace, "g"), newId)
      addPreviewClickHandlersToButtonsIn(node)
    }
  }
}).observe(document.body, { childList: true, subtree: true })
