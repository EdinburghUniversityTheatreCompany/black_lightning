
//Script to display a modal that asks the user if they want to view their profile when they click on their name or profile picture in the menu.
function userModal(title, message, user_profile_url) {
  // Treat confirmation as wanting to view the user profile.
  Swal.fire({
    // Define the modal's properties
    icon: 'question',
    title: title,
    text: message,
    showConfirmButton: true,
    confirmButtonText: 'View User Profile',
    showCloseButton: true,
    showCancelButton: true,
    cancelButtonText: "Close"
  // Determine how to respond to user input.
  }).then((result) => {
    if (result.isConfirmed) {
      location.assign(user_profile_url)
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
        element.dataset.currentUserPath)
    });
  }
});
