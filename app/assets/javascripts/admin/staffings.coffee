jQuery ->
  $(".staffing-sign-up").click (e) ->
    e.preventDefault()

    button = $(e.target);
    job_id = button.attr("data-job-id");
    button.hide();

    $.ajax
      url: "/admin/staffings/job/" + job_id + "/sign_up.json"
      type: "PUT"
      success: (data) ->
        message = "Thank you for choosing to staff " + data.staffing.show_title + " - " + data.name + ", on " + data.staffing.date + ".";
        showAlert("success", message);

        name = $("<span>" + data.user.first_name + " " + data.user.last_name + "</span>");
        name.hide();
        button.replaceWith(name);
        name.fadeIn();

        return;
      error: (jqXHR, textStatus, errorThrown) ->
        showAlert ("alert", "Error signing up for staffing: " + errorThrown);
        button.show();
        return;
    return false