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
  
  if jQuery(".md").length > 0
    submit = $("input[type='submit']");
    submit.addClass "disabled"
    href = submit.attr("href")
    submit[0].disabled = true;
    submit.attr "title", "You must preview Markdown before saving"
  
  return