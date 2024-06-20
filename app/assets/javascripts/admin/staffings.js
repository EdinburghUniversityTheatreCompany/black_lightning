// This script handles the staffing sign up button using JavaScript on the same page rather than page navigation.

jQuery(function() {
  var tried_ajax = false;
  $(".staffing-sign-up").data('handler', function(button) {
    if (tried_ajax) {
      return true;
    }

    var job_id = button.attr("data-job-id");
    button.hide();

    $.ajax({
      url: "/admin/staffings/job/" + job_id + "/sign_up.json",
      type: "PUT",
      success: function(data) {
        // If there was an error, just do the default action and try that way.
        if (data.error) {
          tried_ajax = true;
          button.click();
          return;
        }

        var start_time = moment.utc(data.js_start_time * 1000);
        var end_time = moment.utc(data.js_end_time * 1000);

        var start_str = start_time.format("YYYYMMDD[T]HHmmss[Z]");
        var end_str = end_time.format("YYYYMMDD[T]HHmmss[Z]");

        var google_calendar_addr = "http://www.google.com/calendar/event?action=TEMPLATE&text=" + data.name + " - " + data.staffable.show_title + "&dates=" + start_str + "/" + end_str + "&location=Bedlam Theatre, Edinburgh&trp=true&sprop=website:http://www.bedlamtheatre.co.uk&sprop=name:Bedlam Theatre";
        var start_str = start_time.local().calendar();

        // This message is separate from the message set in the controller.
        var message = "<p>Thank you for choosing to staff " + data.staffable.show_title + " as " + data.name + " on " + start_str + ".</p><p><a href=\"" + google_calendar_addr + "\" target=\"_blank\">Add to Google Calendar</a>";
        
        showToast("success", message);

        // Find the original button (rather than the clone in the modal)
        button = $("a[data-job-id=" + job_id + "]").not(".btn-danger");

        var name = $("<span>" + data.user.first_name + " " + data.user.last_name + "</span>");
        name.hide();
        button.replaceWith(name);
        name.fadeIn();

        return;
      },
      error: function(jqXHR, textStatus, errorThrown) {
        window.location.reload(true);
      }
    });
    return false;
  });
});
