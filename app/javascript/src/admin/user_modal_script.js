
function userModal(title, message, user_profile_url, sign_out_url) {
  // Treat confirmation as wanting to view the user profile
  // and denial as wanting to sign out.
  Swal.fire({
    // Define the modal's properties
    icon: 'question',
    title: title,
    text: message,
    showConfirmButton: true,
    confirmButtonText: 'View User Profile',
    showCloseButton: true,
    showCancelButton: true,
    cancelButtonText: "Close",
    showDenyButton: true,
    denyButtonText: 'Log Out'
  // Determine how to respond to user input.
  }).then((result) => {
    if (result.isConfirmed) {
      location.assign(user_profile_url)
    } else if (result.isDenied) {
      // Sign the user out.
      $.ajax({
        url: sign_out_url,
        type: "DELETE",
        headers: {
          'X-CSRF-Token': $('meta[name=csrf-token]').attr('content')
        }
      }).done(function () {
        // And show a confirmation message.
        Swal.fire({
          icon: 'success',
          title: 'Logged out',
          text: 'You were successfully logged out. See you soon!'
        }).then(() => {
          location.assign('/')
        })
      });

    }
  })
}

window.addEventListener('load', function() {
  // The elements that can be clicked to cause the profile/sign out modal to appear. 
  var triggerUserModalElements = document.getElementsByClassName('triggerUserModal');

  // Assign each element a click event that will trigger the userModal function.
  for (let element of triggerUserModalElements) {
    element.addEventListener('click', function() {
      userModal(element.dataset.nameAttr,
        "You're currently logged in. Click view user profile to change your name, password, see shows that you're involved in, and more.",
        element.dataset.currentUserPath, element.dataset.destroyUserPath)
    });
  }
});
