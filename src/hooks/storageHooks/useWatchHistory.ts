import { useEffect, useRef, useState } from "react";
import { useAuthProvider } from "../../context/AuthContext";
import { useLocalStorage } from "../utilHooks/useLocalStorage";
import {
    collection,
    getDocs,
    addDoc,
    updateDoc,
    deleteDoc,
    doc,
    query,
    where,
    limit,
    Timestamp,
} from "firebase/firestore";
import { db } from "../../firebase/firebase";

export type WatchHistoryItem = {
    mediaType: "movie" | "tv";
    mediaId: number;
    season?: string;
    episode?: string;
    currentTime: number;
    updatedAt: Date;
    firebaseId?: string;
};

export const useWatchHistory = () => {
    const { user } = useAuthProvider();
    const { get, set } = useLocalStorage();

    const [history, setHistory] = useState<WatchHistoryItem[]>([]);
    const historyRef = useRef<WatchHistoryItem[]>([]);
    const inFlightRef = useRef<Record<string, boolean>>({});

    useEffect(() => {
        historyRef.current = history;
    }, [history]);

    useEffect(() => {
        const load = async () => {
            if (user?.uid) {
                const q = query(collection(db, "users", user.uid, "watchHistory"));
                const snapshot = await getDocs(q);

                const data: WatchHistoryItem[] = snapshot.docs.map((docSnap) => {
                    const d = docSnap.data();

                    return {
                        firebaseId: docSnap.id,
                        mediaType: d.mediaType,
                        mediaId: d.mediaId,
                        season: d.season,
                        episode: d.episode,
                        currentTime: d.currentTime,
                        updatedAt: d.updatedAt instanceof Timestamp
                            ? d.updatedAt.toDate()
                            : new Date(d.updatedAt),
                    };
                });

                setHistory(data);
            } else {
                const local = get<WatchHistoryItem[]>("watch-history", []);
                setHistory(local);
            }
        };

        load();
    }, [user?.uid]);

    const upsertHistory = async (entry: WatchHistoryItem) => {
        const key = `${entry.mediaType}-${entry.mediaId}`;

        if (inFlightRef.current[key]) return;
        inFlightRef.current[key] = true;

        try {
            if (user?.uid) {
                const q = query(
                    collection(db, "users", user.uid, "watchHistory"),
                    where("mediaId", "==", entry.mediaId),
                    where("mediaType", "==", entry.mediaType),
                    limit(1)
                );

                const snapshot = await getDocs(q);

                const payload = {
                    mediaType: entry.mediaType,
                    mediaId: entry.mediaId,
                    season: entry.season ?? null,
                    episode: entry.episode ?? null,
                    currentTime: entry.currentTime,
                    updatedAt: Timestamp.fromDate(entry.updatedAt),
                };

                if (!snapshot.empty) {
                    const existingDoc = snapshot.docs[0];
                    await updateDoc(
                        doc(db, "users", user.uid, "watchHistory", existingDoc.id),
                        payload
                    );
                } else {
                    await addDoc(
                        collection(db, "users", user.uid, "watchHistory"),
                        payload
                    );
                }

                // 🔥 IMPORTANT:
                // Do NOT call setHistory here.
                // MediaPlayer should not rerender on pause/write.
                return;
            }

            const existing = get<WatchHistoryItem[]>("watch-history", []);
            const index = existing.findIndex(
                (h) =>
                    h.mediaId === entry.mediaId &&
                    h.mediaType === entry.mediaType
            );

            if (index !== -1) {
                existing[index] = entry;
            } else {
                existing.unshift(entry);
            }

            existing.sort(
                (a, b) =>
                    new Date(b.updatedAt).getTime() -
                    new Date(a.updatedAt).getTime()
            );

            set("watch-history", existing);
            historyRef.current = existing;
            setHistory(existing);
        } finally {
            inFlightRef.current[key] = false;
        }
    };

    const removeHistory = async (entry: WatchHistoryItem) => {
        if (user?.uid) {
            const q = query(
                collection(db, "users", user.uid, "watchHistory"),
                where("mediaId", "==", entry.mediaId),
                where("mediaType", "==", entry.mediaType),
                limit(1)
            );

            const snapshot = await getDocs(q);

            if (!snapshot.empty) {
                await deleteDoc(
                    doc(db, "users", user.uid, "watchHistory", snapshot.docs[0].id)
                );
            }

            setHistory((prev) =>
                prev.filter(
                    (h) =>
                        !(
                            h.mediaId === entry.mediaId &&
                            h.mediaType === entry.mediaType
                        )
                )
            );
            return;
        }

        const updated = historyRef.current.filter(
            (h) =>
                !(
                    h.mediaId === entry.mediaId &&
                    h.mediaType === entry.mediaType
                )
        );

        set("watch-history", updated);
        historyRef.current = updated;
        setHistory(updated);
    };

    const clearHistory = async () => {
        if (user?.uid) {
            const q = query(collection(db, "users", user.uid, "watchHistory"));
            const snapshot = await getDocs(q);

            await Promise.all(
                snapshot.docs.map((d) =>
                    deleteDoc(doc(db, "users", user.uid!, "watchHistory", d.id))
                )
            );

            setHistory([]);
            historyRef.current = [];
            return;
        }

        set("watch-history", []);
        historyRef.current = [];
        setHistory([]);
    };

    const getHistoryItem = (mediaId: number, mediaType: "movie" | "tv") => {
        return historyRef.current.find(
            (h) => h.mediaId === mediaId && h.mediaType === mediaType
        );
    };

    return {
        history,
        upsertHistory,
        removeHistory,
        clearHistory,
        getHistoryItem,
    };
};