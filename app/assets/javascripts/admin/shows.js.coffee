jQuery ->
  $('.xts_lookup').click (e) ->
    e.preventDefault()

    show_name = $('#show_name').val()

    $.ajax
      url: "/admin/shows/query_xts.json?name=#{show_name}"
      success: (data) ->
        if data.length == 0
          message = "XTS details not found."
          showAlert "alert", message

        $('#show_xts_id').val(data[0].id)
        $('#show_tagline').val(data[0].tagline)

        start_date = new Date(data[0].firstperformance * 1000)
        end_date   = new Date(data[0].lastperformance * 1000)

        $('#show_start_date_1i').val(start_date.getFullYear())
        $('#show_start_date_2i').val(start_date.getMonth() + 1)
        $('#show_start_date_3i').val(start_date.getDate())

        $('#show_end_date_1i').val(end_date.getFullYear())
        $('#show_end_date_2i').val(end_date.getMonth() + 1)
        $('#show_end_date_3i').val(end_date.getDate())

        message = "XTS details loaded."
        showAlert "success", message

        return

    return false
  return