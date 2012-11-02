# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://jashkenas.github.com/coffee-script/
  
jQuery ->
  jQuery("a[href$=\"preview\"]").on "shown", (e) ->
    id = $(e.currentTarget).data('preview-id');
    $('#' + id + '_preview').html(markdown.toHTML($('.md').val()));
    return
  
  return