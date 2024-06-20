// Uses the Toast and PersistentToast method defined in the index.js file to display flash messages.
async function showToast(alert_type, message) {
  await Toast.fire({
  icon: alert_type,
  title: message
  }) 
}

async function showPersistentToast (alert_type, message) {
  await PersistentToast.fire({
  icon: alert_type,
  title: message,
  position: 'top'
  })
}

async function showError (message) {
  await Swal.fire({
  icon: 'error',
  title: 'Oops...',
  html: message,
  allowOutsideClick: () => {
      const popup = Swal.getPopup()
      popup.classList.remove('swal2-show')
      setTimeout(() => {
      popup.classList.add('animate__animated', 'animation__shake')
      })
      setTimeout(() => {
      popup.classList.remove('animate__animated', 'animation__shake')
      }, 500)
      return false
  }
  })
}
// Render each flash message by type. If the type is not success or error, it will be rendered as a persistent toast.
export async function showFlashAlerts(flash) {
  for (const [alertType, message] of Object.entries(flash)) {
    switch (alertType) {
      case 'success':
        await showToast(alertType, message);
        break;
      case 'error':
        await showError(`<div class="text-justify">${message}</div>`);
        break;
      default:
        await showPersistentToast(alertType, message);
        break;
    }
  }
}

// Make this available to inline methods.
window.showFlashAlerts = showFlashAlerts;