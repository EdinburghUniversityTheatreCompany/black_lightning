import swal from 'sweetalert2/dist/sweetalert2.js'
import Rails from '@rails/ujs';
import './alerts'

window.Swal = swal;

const Toast = Swal.mixin({
  toast: true,
  position: 'top-end',
  showConfirmButton: false,
  timer: 4500,
  customClass: {
    popup: 'colored-toast'
  },
  didOpen: (toast) => {
    toast.addEventListener('mouseenter', Swal.stopTimer)
    toast.addEventListener('mouseleave', Swal.resumeTimer)
  },
  iconColor: 'white'
})

const PersistentToast = Swal.mixin({
  toast: true,
  showConfirmButton: true,
  timerProgressBar: false
})

// Make these methods available to the window object, so that they can be used in inline scripts.
window.Toast = Toast;
window.PersistentToast = PersistentToast;

Rails.confirm = function (message, element) {
  const swalWithBootstrap = swal.mixin({
    buttonsStyling: true,
  });

  swalWithBootstrap
    .fire({
      icon: 'warning',
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
