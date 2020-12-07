// Converted from CoffeeScript using decaffeinate

const importFromXTS = function(data, index) {
  $('#show_xts_id').val(data[index].id);
  // $('#show_tagline').val(data[index].tagline)

  // start_date = new Date(data[index].firstperformance * 1000)
  // end_date   = new Date(data[index].lastperformance * 1000)

  // $('#show_start_date_1i').val(start_date.getFullYear())
  // $('#show_start_date_2i').val(start_date.getMonth() + 1)
  // $('#show_start_date_3i').val(start_date.getDate())

  // $('#show_end_date_1i').val(end_date.getFullYear())
  // $('#show_end_date_2i').val(end_date.getMonth() + 1)
  // $('#show_end_date_3i').val(end_date.getDate())

  const message = "XTS details loaded.";
  return showAlert("success", message);
};

const addXTSLookup = function() {
  $('.xts_lookup').click(function(e) {
    e.preventDefault();

    const show_name = $('#show_name').val();

    $.ajax({
      url: `/admin/shows/query_xts.json?name=${show_name}`,
      success(data) {
        let message;
        if (data.length === 0) {
          message = "XTS details not found.";
          showAlert("alert", message);
          return;
        }

        if (data.length === 1) {
          importFromXTS(0);
          return;
        }

        message = `\
<p>Many XTS entries were found with this name. Please select the correct entry</p>\
`;

        const ul = $("<ul></ul>");

        $.each(data, function(i, item) {
          const date = new Date(item.firstperformance * 1000);
          const date_str = `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear()}`;
          const li = `\
<li><a class=".xts_id_select" data-index="${i}">${item.name} - ${date_str}</a></li>\
`;
          ul.append(li);
        });

        const $message = $(message).append(ul);

        $message.find('a').click(function(e) {
          const a = e.target;
          const index = $(a).data("index");

          alert.slideUp();
          importFromXTS(data, index);
        });

        var alert = showAlert("notice", $message);

      }
    });

    return false;
  });
};


jQuery(() => addXTSLookup());