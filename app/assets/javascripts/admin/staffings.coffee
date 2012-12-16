jQuery ->
  tried_ajax = false;
  $(".staffing-sign-up").data 'handler', (button) ->
    return if tried_ajax;

    job_id = button.attr("data-job-id");
    button.hide();

    $.ajax
      url: "/admin/staffings/job/" + job_id + "/sign_up.json"
      type: "PUT"
      success: (data) ->
        #if there was an error, just do the default action and try that way.
        if data.error
          tried_ajax = true
          button.click()
          return

        message = "Thank you for choosing to staff " + data.staffing.show_title + " - " + data.name + ", on " + data.staffing.date + ".";
        showAlert "success", message;

        name = $("<span>" + data.user.first_name + " " + data.user.last_name + "</span>");
        name.hide();
        button.replaceWith(name);
        name.fadeIn();

        return;
      error: (jqXHR, textStatus, errorThrown) ->
        tried_ajax = true
        button.click()
        return
    return false