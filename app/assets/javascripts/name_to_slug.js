$(document).ready(function(){
  $('#event_name').keyup(function() {
      var slug = jQuery.trim($('#event_name').val()).replace(/\s+/g,'-').replace(/[^a-zA-Z0-9\-]/g,'').toLowerCase().replace(/\-{2,}/g,'-');
      $('#event_slug').val(slug);
  });
});