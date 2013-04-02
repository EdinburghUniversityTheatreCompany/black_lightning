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

        start_time = moment.utc(data.js_start_time * 1000)
        end_time = moment.utc(data.js_end_time * 1000)

        start_str = start_time.format("YYYYMMDD[T]HHmmss[Z]")
        end_str = end_time.format("YYYYMMDD[T]HHmmss[Z]")

        google_calendar_addr = """
                               http://www.google.com/calendar/event
                                 ?action=TEMPLATE
                                 &text=#{data.name} - #{data.staffable.show_title}
                                 &dates=#{start_str}/#{end_str}
                                 &location=Bedlam Theatre, Edinburgh
                                 &trp=true
                                 &sprop=website:http://www.bedlamtheatre.co.uk
                                 &sprop=name:Bedlam Theatre
                               """

        # Remove the linebreaks added above for readability.
        google_calendar_addr = google_calendar_addr.replace(/(\r\n|\n|\r)\s\s/gm,"");

        start_str = start_time.local().calendar()

        message = """
                  <p>Thank you for choosing to staff #{data.staffable.show_title} - #{data.name} #{start_str}.</p>
                  <p><a href="#{google_calendar_addr}" target="_blank">Add to Google Calendar</a>
                  """
        showAlert "success", message;

        #Find the original button (rather than the clone in the modal)
        button = $("a[data-job-id=#{job_id}]").not(".btn-danger")

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