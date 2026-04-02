import { initializeApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";

const firebaseConfig = {
  apiKey: import.meta.env.VITE_TMDB_API_KEY,
  authDomain: "debugging-98550.firebaseapp.com",
  projectId: "debugging-98550",
  storageBucket: "debugging-98550.appspot.com",
  messagingSenderId: "794133279425",
  appId: "1:794133279425:web:a5c2db86a07efdaaf89a40",
  measurementId: "G-HQ1VPNCJME"
};

const app = initializeApp(firebaseConfig);

export const db = getFirestore(app);