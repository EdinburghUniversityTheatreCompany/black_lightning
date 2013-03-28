$ ->
  window.NestedFormEvents.prototype.insertFields = (content, assoc, link) ->
    if $(link).parent().is('li')
      $li = $(link).closest('li');
      return $(content).insertBefore($li);

    return $(content).insertBefore(link);