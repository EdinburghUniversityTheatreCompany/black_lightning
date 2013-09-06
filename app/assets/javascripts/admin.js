// This is a manifest file that'll be compiled into admin.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// the compiled file.
//
// WARNING: THE FIRST BLANK LINE MARKS THE END OF WHAT'S TO BE PROCESSED, ANY BLANK LINE SHOULD
// GO AFTER THE REQUIRES BELOW.
//
//= require admin/jquery.gridster.min
//= require admin/moment
//= require admin/nested_forms
//= require admin/md_editor
//= require admin/staffings
//= require admin/shows
//= require alerts
//= require admin/modal_confirmation

(function () {
  var grid

  function createCookie(name,value,days) {
    var date = new Date();
    date.setTime(date.getTime()+(days*24*60*60*1000));

    var expires = "; expires="+date.toGMTString();

    document.cookie = name+"="+value+expires+"; path=/";
  }

  function readCookie(name) {
    var nameEQ = name + "=";
    var ca = document.cookie.split(';');
    for(var i=0;i < ca.length;i++) {
      var c = ca[i];
      while (c.charAt(0)==' ') c = c.substring(1,c.length);
      if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
    }
    return null;
  }

  function updateCookie() {
    value = JSON.stringify(grid.serialize());
    createCookie("dashboard_pos", value, 3600);
  }

  $(window).load(function() {
    //Don't load gridster if the window is too small.
    if ($('body').width() < 979) {
      return
    }

    var existing_pos = JSON.parse(readCookie('dashboard_pos'));
    if (existing_pos) {
      //Load from cookie
      $.each(existing_pos, function(i, item) {
        var dashboard_item = $(".gridster ul").children().eq(i);
        dashboard_item.attr('data-row', item.row);
        dashboard_item.attr('data-col', item.col);
      });
    }

    grid = $(".gridster ul").gridster({
      widget_margins: [20, 20],
      widget_base_dimensions: [260, 260],
      draggable: {stop: updateCookie}
    });
    grid = grid.data('gridster');
  });
})();