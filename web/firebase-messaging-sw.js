importScripts("https://www.gstatic.com/firebasejs/9.22.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.22.1/firebase-messaging-compat.js");

// మీ Firebase Project Config వివరాలను ఇక్కడ ఇవ్వండి (web/index.html లో ఉన్న వివరాలు)
firebase.initializeApp({
  apiKey: "AIzaSyAzUtLhqstRYZcEdvX8_xXxtSlxlHfisYo",
  authDomain: "flash2mart.firebaseapp.com",
  projectId: "flash2mart",
  storageBucket: "flash2mart.appspot.com",
  messagingSenderId: "1058492345678",
  appId: "1:1058492345678:web:a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});