importScripts("https://www.gstatic.com/firebasejs/10.0.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.0.0/firebase-messaging-compat.js");

self.addEventListener("push", () => {});
self.__WB_DISABLE_DEV_LOGS = true;

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



const CACHE_NAME = "app-cache-v2"; 
const OFFLINE_URL = "/offline.html";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll([
        OFFLINE_URL,
        "/logo/streamify-logo.png", 
      ]);
    })
  );

  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    })
  );

  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const request = event.request;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request).catch(() => caches.match(OFFLINE_URL))
    );
    return;
  }

  if (request.url.includes("/logo/")) {
    event.respondWith(
      caches.match(request).then((cached) => {
        return cached || fetch(request);
      })
    );
    return;
  }
});