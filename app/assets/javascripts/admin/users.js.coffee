updatePage = (data) ->
  new_table = $(data).find('.table')
  new_table.hide()
  new_pagination = $(data).find('.pagination')
  new_pagination.hide()

  $('.table').replaceWith(new_table)
  new_table.fadeIn()
  $('.paginate_holder').empty();
  $('.paginate_holder').append(new_pagination)
  new_pagination.fadeIn()

updateHistory = (param, value) ->
  path = location.toString()

  if path.indexOf("?") == -1
    # Add the parameter
    history.pushState(null, "Users", path + "?#{param}=#{value}");
  else
    if path.indexOf(param) == -1
      # Append the new parameter
      history.pushState(null, "Users", path + "&#{param}=#{value}");
    else
      path = path.replace(new RegExp("(#{param}=)[^\&]*"), '$1' + value);
      history.pushState(null, "Users", path);
  return


$ ->
  search_textbox = $('#search input[type="text"]')
  search_textbox.keyup ->
    searchStr = search_textbox.val()
    setTimeout (->
        if searchStr == search_textbox.val()
          $('.table').fadeOut()
          $('.pagination').fadeOut()

          $.get(location.toString(),
            search: searchStr
            , (data) ->
              updateHistory("search", searchStr)
              updatePage(data)
              return
            )
        return
      ), 500
    return

  show_non_members = $('#show_non_members')
  show_non_members.change ->
    show = show_non_members.is(':checked')
    $.get(location.toString(),
      show_non_members: show
      , (data) ->
        updateHistory("show_non_members", show)
        updatePage(data)
        return
      )
    return
  return