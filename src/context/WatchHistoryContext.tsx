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

import { useQueries } from "@tanstack/react-query";

import { useAuthProvider } from "./AuthContext";
import { useLocalStorage } from "../hooks/utilHooks/useLocalStorage";
import { db } from "../firebase/firebase";
import type { TMDBMedia } from "../types/TMDBMediaType";
import { useTMDBByIds } from "../hooks/mediaHooks/tmdbHooks/useTMDBByIds";

export type WatchHistoryItem = {
    mediaType: "movie" | "tv";
    mediaId: number;
    season?: string;
    episode?: string;
    updatedAt: Date;
    firebaseId?: string;
};

type HistoryMedia = TMDBMedia & {
    season?: string;
    episode?: string;
    updatedAt: Date;
};

type ContextType = {
    history: WatchHistoryItem[];
    historyMedia: HistoryMedia[];
    isLoading: boolean;
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

// 🔥 TMDB fetch (cached by React Query)
const fetchMedia = async (mediaId: number, mediaType: string): Promise<TMDBMedia> => {
    const res = await fetch(
        `https://api.themoviedb.org/3/${mediaType}/${mediaId}?api_key=${import.meta.env.VITE_TMDB_API_KEY}`
    );

    if (!res.ok) throw new Error("Failed to fetch");

    const data = await res.json();

    return {
        ...data,
        mediaType
    };
};

export const WatchHistoryProvider = ({ children }: { children: ReactNode }) => {
    const { user } = useAuthProvider();
    const { get, set } = useLocalStorage();

    const [history, setHistory] = useState<WatchHistoryItem[]>([]);
    const historyRef = useRef<WatchHistoryItem[]>([]);

    useEffect(() => {
        historyRef.current = history;
    }, [history]);

    // 🔹 LOAD history refs
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

                // 🔥 sort newest first
                data.sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime());

                setHistory(data);
            } else {
                const local = get<WatchHistoryItem[]>("watch-history", []);

                local.sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime());

                setHistory(local);
            }
        };

        load();
    }, [user?.uid]);

    const { media, isLoading } = useTMDBByIds(
        history.map(h => ({
            mediaId: h.mediaId,
            mediaType: h.mediaType
        }))
    );
    const historyMedia: HistoryMedia[] = media.map(m => {
        const meta = history.find(
            h => h.mediaId === m.id && h.mediaType === m.mediaType
        );

        if (!meta) return null; 

        return {
            ...m,
            season: meta.season,
            episode: meta.episode,
            updatedAt: meta.updatedAt
        };
    }).filter(Boolean) as HistoryMedia[];

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

        const existing = get<WatchHistoryItem[]>("watch-history", []);

        const index = existing.findIndex(
            h => h.mediaId === entry.mediaId && h.mediaType === entry.mediaType
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

    // 🔹 REMOVE
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
            value={{
                history,
                historyMedia,
                isLoading,
                saveHistory,
                removeHistory,
                getHistoryItem
            }}
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