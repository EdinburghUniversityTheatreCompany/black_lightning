function showAlert(level, body) {
  var alertclass,
      icon;

  switch (level) {
    case 'alert':
      alertclass = "alert-danger";
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

  // BOOTSTRAP NICETOHAVE: Copy from alert_message.erb to make sure it is appropriate.
  var alert = $(
    '<p id="' + level + '" class="alert ' + alertclass + '">' +
      '<i class="' + icon + ' icon-large" aria-hidden=”true”></i>' +
      '<button type="button" class="close" data-dismiss="alert">&times;</button>' +
      '<span class="alert_body"></span>' +
    '</p>');

  $(alert).find(".alert_body").replaceWith(body)

  alert.hide();
  $('.alert-container').append(alert);
  alert.slideDown();

  return alert
}