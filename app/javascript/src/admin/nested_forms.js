// Converted from CoffeeScript using decaffeinate

$(() => window.NestedFormEvents.prototype.insertFields = function(content, assoc, link) {
  if ($(link).parent().is('li')) {
    const $li = $(link).closest('li');
    return $(content).insertBefore($li);
  }

  return $(content).insertBefore(link);
});