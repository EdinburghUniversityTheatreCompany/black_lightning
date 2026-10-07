// SweetAlert "Are you sure?" dialog; resolves true when confirmed.
export function confirmDialog(message) {
  return window.Swal.fire({
    icon: "warning",
    title: "Are you sure?",
    text: message,
    showCancelButton: true,
    confirmButtonText: "Yes",
    cancelButtonText: "Cancel",
  }).then((result) => result.isConfirmed)
}
