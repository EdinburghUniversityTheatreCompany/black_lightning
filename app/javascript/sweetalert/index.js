import swal from "sweetalert2";
import Rails from "@rails/ujs";

Rails.confirm = function (message, element) {
  const swalWithBootstrap = swal.mixin({
    buttonsStyling: true,
  });

  swalWithBootstrap
    .fire({
      html: message,
      title: "Are you sure?",
      showCancelButton: true,
      confirmButtonText: "Yes",
      cancelButtonText: "Cancel",
    })
    .then((result) => {
      if (result.value) {
        console.log("sweetalert finished");
        element.removeAttribute("data-confirm");
        element.click();
      }
    });
};
