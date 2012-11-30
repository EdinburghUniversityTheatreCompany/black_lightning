function showAlert(level, text) {
  var alertclass,
      icon;

  switch (level) {
    case 'alert':
      alertclass = "alert-error";
      icon       = "icon-exclamation-sign";
      break;
    case 'success':
      alertclass = "alert-success";
      icon       = "icon-ok";
      break;
    case 'notice':
      alertclass = "alert-info";
      icon       = "icon-info-sign";
      break;
  }

  var alert = $(
    '<p id="' + level + '" class="alert ' + alertclass + '">' +
      '<i class="' + icon + ' icon-large"></i>' +
      text +
      '<button type="button" class="close" data-dismiss="alert">&times;</button>' +
    '</p>');

  alert.hide();
  $('.alert-container').append(alert);
  alert.slideDown();
}