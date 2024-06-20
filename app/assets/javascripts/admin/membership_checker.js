// Script for the membership checker. This script is used to check if a user is a member of the site using the check_membership action in the membership conmembership

document.addEventListener('DOMContentLoaded', function () {
    var form = document.querySelector('form');

    // Wait for the form to be submitted. When it is, send a request to the server to check if the name entered matches an existing user.
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var formData = new FormData(form);
      var searchParams = new URLSearchParams(formData).toString();
  
      fetch("/admin/membership/check_membership?" + searchParams)
      .then(response => response.json())
      .then(data => {
        // If the user is not found, show an error alert.
        if (data.response === "Member not found")  {
          showResult("error", data.response);
        }
    
        // If we have found the user, show a success alert.
        showResult("success", data.response, data.image);
      })
      .catch(error => {
        showResult("error", error.responseJSON.response);
      });

      document.getElementById('membershipSearch').value = "";
      document.getElementById('membershipSearch').focus();

      return false;
    });
  
    // Create an alert below the form that displays the result of the search.
    function showResult(type, message, imageUrl = null) {
      if(imageUrl) {
        Swal.fire({
          icon: type,
          title: message,
          imageUrl: imageUrl,
          imageWidth: 150,
          imageHeight: 150,
          imageAlt: "User Avatar"
        })
      } else {
        Swal.fire({
          icon: type,
          title: message
        })
      }
    }
});