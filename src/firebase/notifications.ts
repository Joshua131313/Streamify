import { getToken } from "firebase/messaging";
import { messaging } from "./firebase";

export const requestNotificationPermission = async () => {
    try {
        const permission = await Notification.requestPermission();

        if (permission !== "granted") {
            console.log("Permission denied");
            return null;
        }

        const registration = await navigator.serviceWorker.register("/sw.js");

        console.log("SW REGISTERED:", registration);

        const token = await getToken(messaging, {
            vapidKey: import.meta.env.VITE_FIREBASE_VAPID_KEY,
            serviceWorkerRegistration: registration,
        });

        console.log("TOKEN:", token);

        return token;

    } catch (err) {
        console.error("ERROR GETTING TOKEN:", err);
        return null;
    }
};