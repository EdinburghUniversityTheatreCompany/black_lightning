# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://jashkenas.github.com/coffee-script/
  
jQuery ->
  jQuery("a[href=\"#preview\"]").on "shown", (e) ->
    $('#preview').html(markdown.toHTML($('.md').val()));
    submit = $("input[type='submit']");
    submit.removeClass "disabled"
    submit[0].disabled = false;
    submit.attr "title", ""
    return
  
  return