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
import type { TMDBMedia } from "../types/TMDBMediaType";
import { useTMDBByIds } from "../hooks/mediaHooks/tmdbHooks/useTMDBByIds";


export type WatchHistoryItem = {
    mediaType: "movie" | "tv";
    mediaId: number;
    season?: number;
    episode?: number;
    updatedAt: Date;
    firebaseId?: string;
};

type HistoryMedia = TMDBMedia & {
    season?: number;
    episode?: number;
    updatedAt: Date;
};

type ContextType = {
    history: WatchHistoryItem[];
    historyMedia: HistoryMedia[];
    isLoading: boolean;
    saveHistory: (entry: {
        mediaType: "movie" | "tv";
        mediaId: number;
        season?: number;
        episode?: number;
    }) => Promise<void>;
    removeHistory: (mediaId: number, mediaType: "movie" | "tv") => Promise<void>;
    getHistoryItem: (
        mediaId: number,
        mediaType: "movie" | "tv"
    ) => WatchHistoryItem | undefined;
};

const WatchHistoryContext = createContext<ContextType | null>(null);


const normalizeDate = (d: any): Date => {
    if (d instanceof Date) return d;
    return new Date(d);
};


export const WatchHistoryProvider = ({ children }: { children: ReactNode }) => {
    const { user } = useAuthProvider();
    const { get, set } = useLocalStorage();

    const [history, setHistory] = useState<WatchHistoryItem[]>([]);
    const historyRef = useRef<WatchHistoryItem[]>([]);

    useEffect(() => {
        historyRef.current = history;
    }, [history]);


    useEffect(() => {
        const load = async () => {
            if (user?.uid) {
                const snapshot = await getDocs(
                    collection(db, "users", user.uid, "watchHistory")
                );

                const data: WatchHistoryItem[] = snapshot.docs.map(docSnap => {
                    const d = docSnap.data();

                    return {
                        firebaseId: docSnap.id,
                        mediaType: d.mediaType,
                        mediaId: d.mediaId,
                        season: d.season ? Number(d.season) : undefined,
                        episode: d.episode ? Number(d.episode) : undefined,
                        updatedAt: (d.updatedAt as Timestamp).toDate(),
                    };
                });

                data.sort(
                    (a, b) =>
                        b.updatedAt.getTime() - a.updatedAt.getTime()
                );

                setHistory(data);
            } else {
                const local = get<any[]>("watch-history", []);

                const normalized: WatchHistoryItem[] = local.map(item => ({
                    ...item,
                    updatedAt: normalizeDate(item.updatedAt),
                }));

                normalized.sort(
                    (a, b) =>
                        b.updatedAt.getTime() - a.updatedAt.getTime()
                );

                setHistory(normalized);
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

    const historyMedia: HistoryMedia[] = media
        .map(m => {
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
        })
        .filter(Boolean) as HistoryMedia[];


    const saveHistory = async (entry: {
        mediaType: "movie" | "tv";
        mediaId: number;
        season?: number;
        episode?: number;
    }) => {
        const now = new Date();

        const payload: any = {
            mediaType: entry.mediaType,
            mediaId: entry.mediaId,
            updatedAt: now,
        };

        if (entry.season !== undefined) {
            payload.season = entry.season;
        }

        if (entry.episode !== undefined) {
            payload.episode = entry.episode;
        }

        const updateLocalHistory = (item: WatchHistoryItem) => {
            const existing = historyRef.current;

            const index = existing.findIndex(
                h => h.mediaId === item.mediaId && h.mediaType === item.mediaType
            );

            let updated: WatchHistoryItem[];

            const normalizedItem = {
                ...item,
                updatedAt: normalizeDate(item.updatedAt),
            };

            if (index !== -1) {
                updated = [...existing];
                updated[index] = {
                    ...updated[index],
                    ...normalizedItem,
                };
            } else {
                updated = [normalizedItem, ...existing];
            }

            updated.sort(
                (a, b) =>
                    b.updatedAt.getTime() - a.updatedAt.getTime()
            );

            historyRef.current = updated;
            setHistory(updated);
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
                const firebaseId = snapshot.docs[0].id;

                await updateDoc(
                    doc(db, "users", user.uid, "watchHistory", firebaseId),
                    {
                        ...payload,
                        updatedAt: Timestamp.fromDate(now),
                    }
                );

                updateLocalHistory({
                    ...payload,
                    firebaseId,
                });
            } else {
                const docRef = await addDoc(
                    collection(db, "users", user.uid, "watchHistory"),
                    {
                        ...payload,
                        updatedAt: Timestamp.fromDate(now),
                    }
                );

                updateLocalHistory({
                    ...payload,
                    firebaseId: docRef.id,
                });
            }

            return;
        }


        const existing = get<any[]>("watch-history", []);

        const normalizedExisting = existing.map(item => ({
            ...item,
            updatedAt: normalizeDate(item.updatedAt),
        }));

        const index = normalizedExisting.findIndex(
            h => h.mediaId === entry.mediaId && h.mediaType === entry.mediaType
        );

        let updated: WatchHistoryItem[];

        if (index !== -1) {
            updated = [...normalizedExisting];
            updated[index] = payload;
        } else {
            updated = [payload, ...normalizedExisting];
        }

        updated.sort(
            (a, b) =>
                b.updatedAt.getTime() - a.updatedAt.getTime()
        );

        set("watch-history", updated);
        historyRef.current = updated;
        setHistory(updated);
    };


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