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
          showResult("alert", data.response);
          return;
        }
    
        // If we have found the user, show a success alert.
        showResult("success", data.response);

        // If the response has an image (user avatar), add it to the alert.
        if (data.image) {
          var img = document.createElement('img');

          img.src = data.image;
          img.classList.add('img-thumbnail', 'float-right');
          img.style.width = '100px';
      
          document.querySelector('.results-box').appendChild(img);
        }
      })
      .catch(error => {
        showResult("alert", error.responseJSON.response);
      });

      document.getElementById('membershipSearch').value = "";
      document.getElementById('membershipSearch').focus();

      return false;
    });
  
    // Create an alert below the form that displays the result of the search.
    function showResult(type, message) {
      var alertclass, icon;

      switch(type) {
        case "alert":
          alertclass = "alert-danger";
          icon = "fa-exclamation";
          break;
        case "success":
          alertclass = "alert-success";
          icon = "fa-check";
          break;
      }

      var alert = document.createElement("div");
      
      alert.id = type;
      alert.classList.add("alert", alertclass);
      alert.innerHTML = "<i class='" + icon + " fas fa-large' aria-hidden='true'></i> " + message;

      document.querySelector('.results-box').innerHTML = "";
      document.querySelector('.results-box').appendChild(alert);
    }
});