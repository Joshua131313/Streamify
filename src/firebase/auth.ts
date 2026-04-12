import { doc, serverTimestamp, setDoc, collection, addDoc } from "firebase/firestore";
import { db } from "./firebase";

export const createUserDocument = async (
    uid: string,
    email: string | null,
    firstName?: string,
    lastName?: string,
    fullName?: string
) => {
    if (!firstName && !lastName && fullName) {
        const parts = fullName.split(" ");
        firstName = parts[0] || "";
        lastName = parts.slice(1).join(" ") || "";
    }

    const rawSearch = localStorage.getItem("search-history");
    const rawShows = localStorage.getItem("show-history");

    let searchHistory: any[] = [];
    let showHistory: any[] = [];

    try {
        searchHistory = rawSearch ? JSON.parse(rawSearch) : [];
        showHistory = rawShows ? JSON.parse(rawShows) : [];
    } catch {
        console.warn("Failed to parse localStorage");
    }

    await setDoc(
        doc(db, "users", uid),
        {
            userId: uid,
            email,
            firstName: firstName || "",
            lastName: lastName || "",
            createdAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
        },
        { merge: true }
    );

    await Promise.all(
        showHistory.map((item) => {
            const ref = doc(
                db,
                "users",
                uid,
                "showHistory",
                item.showId.toString()
            );

            return setDoc(
                ref,
                {
                    showId: item.showId,
                    season: Number(item.season),
                    episode: Number(item.episode),
                    updatedAt: item.updatedAt
                        ? new Date(item.updatedAt)
                        : serverTimestamp(),
                },
                { merge: true }
            );
        })
    );

    await Promise.all(
        searchHistory.map((item) => {
            const ref = collection(db, "users", uid, "searchHistory");

            return addDoc(ref, {
                searchValue: item.searchValue,
                timeStamp: item.timeStamp
                    ? new Date(item.timeStamp)
                    : serverTimestamp(),
            });
        })
    );
};