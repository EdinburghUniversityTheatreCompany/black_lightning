// Converted from CoffeeSript using decaffeinate

const addHandlers = () => jQuery("a[href$=\"preview\"]").on("shown", function(e) {
  let id = undefined;
  let input = undefined;
  id = $(e.currentTarget).data("preview-id");
  input = $("#" + id + "_input_field textarea");

  $("#" + id + "_preview").html('<b>Please Wait</b>');

  return $.ajax({
    type: 'POST',
    url: '/markdown/preview.json',
    data: JSON.stringify({ input_html: encodeURIComponent(input.val()) }),
    success(data) {
      const preview = $("#" + id + "_preview");
      preview.html(data.rendered_md);
    },
    error(jqXHR, textStatus, errorThrown) {
      const error_data = JSON.parse(jqXHR.responseText);
      const error_html =  `\
<b>There was an error rendering your kramdown.</b>
<pre>${error_data.error}</pre>\
`;
      return $("#" + id + "_preview").html(error_html);
    }
  });
});


jQuery(() => addHandlers());

$(document).on("nested:fieldAdded", function(event) {
  const new_id = new Date().getTime();

  /*
    Slightly hacky way of making all the ids unique and updating the necessary anchors.
  */
  jQuery(event.field).find('[id$="_input_field"]').attr('id', new_id + '_input_field');
  jQuery(event.field).find('[href$="_input_field"]').attr('href', '#' + new_id + '_input_field');
  jQuery(event.field).find('[id$="_preview"]').attr('id', new_id + '_preview');
  jQuery(event.field).find('[href$="_preview"]').attr('href', '#' + new_id + '_preview').attr('data-preview-id', new_id);

  return addHandlers();
});