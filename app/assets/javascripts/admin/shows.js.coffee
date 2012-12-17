importFromXTS = (data, index) ->
  $('#show_xts_id').val(data[index].id)
  # $('#show_tagline').val(data[index].tagline)

  # start_date = new Date(data[index].firstperformance * 1000)
  # end_date   = new Date(data[index].lastperformance * 1000)

  # $('#show_start_date_1i').val(start_date.getFullYear())
  # $('#show_start_date_2i').val(start_date.getMonth() + 1)
  # $('#show_start_date_3i').val(start_date.getDate())

  # $('#show_end_date_1i').val(end_date.getFullYear())
  # $('#show_end_date_2i').val(end_date.getMonth() + 1)
  # $('#show_end_date_3i').val(end_date.getDate())

  message = "XTS details loaded."
  showAlert "success", message

addXTSLookup = ->
  $('.xts_lookup').click (e) ->
    e.preventDefault()

    show_name = $('#show_name').val()

    $.ajax
      url: "/admin/shows/query_xts.json?name=#{show_name}"
      success: (data) ->
        if data.length == 0
          message = "XTS details not found."
          showAlert "alert", message
          return

        if data.length == 1
          importFromXTS(0)
          return

        message = """
                  <p>Many XTS entries were found with this name. Please select the correct entry</p>
                  """

        ul = $("<ul></ul>")

        $.each data, (i, item) ->
          date = new Date(item.firstperformance * 1000)
          date_str = "#{date.getDate()}/#{date.getMonth() + 1}/#{date.getFullYear()}"
          li = """
               <li><a class=".xts_id_select" data-index="#{i}">#{item.name} - #{date_str}</a></li>
               """
          ul.append(li)
          return

        $message = $(message).append(ul)

        $message.find('a').click (e) ->
          a = e.target
          index = $(a).data("index")

          alert.slideUp()
          importFromXTS(data, index)
          return

        alert = showAlert "notice", $message

        return

    return false
  return

addSortable = ->
  $(".sortable").sortable
    stop: (event, ui) ->
      $('.display_order_input').each (i, item) ->
        $(item).val($(item).closest('li').index())
    placeholder: 'ui-sortable-placeholder'
    opacity: 0.6
    containment: 'parent'
    tolerance: 'pointer'
    items: "li:not(.ui-state-disabled)"

jQuery ->
  addXTSLookup()
  addSortable()