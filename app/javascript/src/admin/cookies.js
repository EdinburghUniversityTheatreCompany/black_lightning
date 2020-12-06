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

  $(window).on('load', function() {
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