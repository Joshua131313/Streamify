import {
    createContext,
    useContext,
    useEffect,
    useRef,
    useState,
    type ReactNode,
} from "react";

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

import { useAuthProvider } from "./AuthContext";
import { useLocalStorage } from "../hooks/utilHooks/useLocalStorage";
import { db } from "../firebase/firebase";

export type WatchHistoryItem = {
    mediaType: "movie" | "tv";
    mediaId: number;
    season?: string;
    episode?: string;
    updatedAt: Date;
    firebaseId?: string;
};

type ContextType = {
    history: WatchHistoryItem[];
    saveHistory: (entry: {
        mediaType: "movie" | "tv";
        mediaId: number;
        season?: string;
        episode?: string;
    }) => Promise<void>;
    removeHistory: (mediaId: number, mediaType: "movie" | "tv") => Promise<void>;
    getHistoryItem: (
        mediaId: number,
        mediaType: "movie" | "tv"
    ) => WatchHistoryItem | undefined;
};

const WatchHistoryContext = createContext<ContextType | null>(null);

export const WatchHistoryProvider = ({ children }: { children: ReactNode }) => {
    const { user } = useAuthProvider();
    const { get, set } = useLocalStorage();

    const [history, setHistory] = useState<WatchHistoryItem[]>([]);
    const historyRef = useRef<WatchHistoryItem[]>([]);

    useEffect(() => {
        historyRef.current = history;
    }, [history]);

    // ✅ LOAD ONCE
    useEffect(() => {
        const load = async () => {
            if (user?.uid) {
                const snapshot = await getDocs(
                    collection(db, "users", user.uid, "watchHistory")
                );

                const data = snapshot.docs.map(docSnap => {
                    const d = docSnap.data();
                    return {
                        firebaseId: docSnap.id,
                        mediaType: d.mediaType,
                        mediaId: d.mediaId,
                        season: d.season,
                        episode: d.episode,
                        updatedAt: (d.updatedAt as Timestamp).toDate(),
                    };
                });

                setHistory(data);
            } else {
                setHistory(get("watch-history", []));
            }
        };

        load();
    }, [user?.uid]);

    // 🔥 SAVE (simple + clean)
    const saveHistory = async (entry: {
        mediaType: "movie" | "tv";
        mediaId: number;
        season?: string;
        episode?: string;
    }) => {
const payload: WatchHistoryItem = {
    mediaType: entry.mediaType,
    mediaId: entry.mediaId,
    season: entry.season ?? "",
    episode: entry.episode ?? "",
    updatedAt: new Date(),
};

        if (user?.uid) {
            const q = query(
                collection(db, "users", user.uid, "watchHistory"),
                where("mediaId", "==", entry.mediaId),
                where("mediaType", "==", entry.mediaType),
                limit(1)
            );

            const snapshot = await getDocs(q);

            if (!snapshot.empty) {
                await updateDoc(
                    doc(db, "users", user.uid, "watchHistory", snapshot.docs[0].id),
                    {
                        ...payload,
                        updatedAt: Timestamp.fromDate(payload.updatedAt),
                    }
                );
            } else {
                await addDoc(
                    collection(db, "users", user.uid, "watchHistory"),
                    {
                        ...payload,
                        updatedAt: Timestamp.fromDate(payload.updatedAt),
                    }
                );
            }

            return;
        }

        // local fallback
        const existing = get<WatchHistoryItem[]>("watch-history", []);

        const index = existing.findIndex(
            (h: WatchHistoryItem) =>
                h.mediaId === entry.mediaId &&
                h.mediaType === entry.mediaType
        );

        if (index !== -1) {
            existing[index] = payload;
        } else {
            existing.unshift(payload);
        }

        set("watch-history", existing);
        historyRef.current = existing;
        setHistory(existing);
    };

    // 🔥 REMOVE (used when completed)
    const removeHistory = async (mediaId: number, mediaType: "movie" | "tv") => {
        if (user?.uid) {
            const existing = historyRef.current.find(
                h => h.mediaId === mediaId && h.mediaType === mediaType
            );

            if (existing?.firebaseId) {
                await deleteDoc(
                    doc(
                        db,
                        "users",
                        user.uid,
                        "watchHistory",
                        existing.firebaseId
                    )
                );
            }

            return;
        }

        const updated = historyRef.current.filter(
            h => !(h.mediaId === mediaId && h.mediaType === mediaType)
        );

        set("watch-history", updated);
        historyRef.current = updated;
        setHistory(updated);
    };

    const getHistoryItem = (mediaId: number, mediaType: "movie" | "tv") => {
        return historyRef.current.find(
            h => h.mediaId === mediaId && h.mediaType === mediaType
        );
    };

    return (
        <WatchHistoryContext.Provider
            value={{ history, saveHistory, removeHistory, getHistoryItem }}
        >
            {children}
        </WatchHistoryContext.Provider>
    );
};

export const useWatchHistoryContext = () => {
    const ctx = useContext(WatchHistoryContext);
    if (!ctx) throw new Error("Must be used inside WatchHistoryProvider");
    return ctx;
};