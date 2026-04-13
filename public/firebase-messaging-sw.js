importScripts("https://www.gstatic.com/firebasejs/10.0.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.0.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyCjA-yH-JUxA5n18e8LQMZrpTnVGl9mqW0",
  authDomain: "debugging-98550.firebaseapp.com",
  projectId: "debugging-98550",
  storageBucket: "debugging-98550.appspot.com",
  messagingSenderId: "794133279425",
  appId: "1:794133279425:web:a5c2db86a07efdaaf89a40",
  measurementId: "G-HQ1VPNCJME"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log("Background message:", payload);

  self.registration.showNotification(payload.notification.title, {
    body: payload.notification.body,
    icon: "/logo/streamify-logo.png",
  });
});