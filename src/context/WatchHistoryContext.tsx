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
    orderBy,
    startAfter,
    QueryDocumentSnapshot,
} from "firebase/firestore";

import { useAuthProvider } from "./AuthContext";
import { useLocalStorage } from "../hooks/utilHooks/useLocalStorage";
import { auth, db } from "../firebase/firebase";
import type { TMDBMedia } from "../types/TMDBMediaType";
import { useTMDBByIds } from "../hooks/mediaHooks/tmdbHooks/useTMDBByIds";
import type { TMediaType } from "../types/tmdb";

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
    hasMore: boolean;
    loadMore: () => Promise<void>;
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
    ) => Promise<WatchHistoryItem | undefined>;
};

const WatchHistoryContext = createContext<ContextType | null>(null);

const normalizeDate = (d: any): Date => {
    if (d instanceof Date) return d;
    return new Date(d);
};

const PAGE_SIZE = 20;

export const WatchHistoryProvider = ({ children }: { children: ReactNode }) => {
    const { user } = useAuthProvider();
    const isAuthenticated = !!(user?.uid && !auth.currentUser?.isAnonymous);
    const uid = isAuthenticated && user?.uid ? user.uid : null;
    const { get, set } = useLocalStorage();

    const [history, setHistory] = useState<WatchHistoryItem[]>([]);
    const historyRef = useRef<WatchHistoryItem[]>([]);

    const [lastDoc, setLastDoc] = useState<QueryDocumentSnapshot | null>(null);
    const [hasMore, setHasMore] = useState(true);

    useEffect(() => {
        historyRef.current = history;
    }, [history]);

    const loadInitial = async () => {
        if (!uid) return;

        const q = query(
            collection(db, "users", uid, "watchHistory"),
            orderBy("updatedAt", "desc"),
            limit(PAGE_SIZE)
        );

        const snapshot = await getDocs(q);

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

        setHistory(data);
        historyRef.current = data;

        setLastDoc(snapshot.docs[snapshot.docs.length - 1] || null);
        setHasMore(snapshot.docs.length === PAGE_SIZE);
    };

    const loadMore = async () => {
        if (!uid || !lastDoc || !hasMore) return;

        const q = query(
            collection(db, "users", uid, "watchHistory"),
            orderBy("updatedAt", "desc"),
            startAfter(lastDoc),
            limit(PAGE_SIZE)
        );

        const snapshot = await getDocs(q);

        const newData: WatchHistoryItem[] = snapshot.docs.map(docSnap => {
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

        const updated = [...historyRef.current, ...newData];

        historyRef.current = updated;
        setHistory(updated);

        setLastDoc(snapshot.docs[snapshot.docs.length - 1] || null);
        setHasMore(snapshot.docs.length === PAGE_SIZE);
    };

    useEffect(() => {
        if (isAuthenticated) {
            loadInitial();
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
            historyRef.current = normalized;
            setHasMore(false);
        }
    }, [isAuthenticated]);

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

        if (entry.season !== undefined) payload.season = entry.season;
        if (entry.episode !== undefined) payload.episode = entry.episode;

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

        if (isAuthenticated) {
            if (uid) {
                const q = query(
                    collection(db, "users", uid, "watchHistory"),
                    where("mediaId", "==", entry.mediaId),
                    where("mediaType", "==", entry.mediaType),
                    limit(1)
                );

                const snapshot = await getDocs(q);

                if (!snapshot.empty) {
                    const firebaseId = snapshot.docs[0].id;

                    await updateDoc(
                        doc(db, "users", uid, "watchHistory", firebaseId),
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
                        collection(db, "users", uid, "watchHistory"),
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
        };
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
    }

    const removeHistory = async (mediaId: number, mediaType: "movie" | "tv") => {
        if (uid) {
            const existing = historyRef.current.find(
                h => h.mediaId === mediaId && h.mediaType === mediaType
            );

            if (existing?.firebaseId) {
                await deleteDoc(
                    doc(
                        db,
                        "users",
                        uid,
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

    const getHistoryItem = async (
        mediaId: number,
        mediaType: "movie" | "tv"
    ): Promise<WatchHistoryItem | undefined> => {
        const localHit = historyRef.current.find(
            h => h.mediaId === mediaId && h.mediaType === mediaType
        );

        if (localHit) return localHit;

        if (uid) {
            const q = query(
                collection(db, "users", uid, "watchHistory"),
                where("mediaId", "==", mediaId),
                where("mediaType", "==", mediaType),
                limit(1)
            );

            const snapshot = await getDocs(q);

            if (snapshot.empty) return undefined;

            const docSnap = snapshot.docs[0];
            const d = docSnap.data();

            return {
                firebaseId: docSnap.id,
                mediaType: d.mediaType,
                mediaId: d.mediaId,
                season: d.season ? Number(d.season) : undefined,
                episode: d.episode ? Number(d.episode) : undefined,
                updatedAt: (d.updatedAt as Timestamp).toDate(),
            };
        }

        const local = get<any[]>("watch-history", []);

        const item = local.find(
            h => h.mediaId === mediaId && h.mediaType === mediaType
        );

        if (!item) return undefined;

        return {
            ...item,
            updatedAt: normalizeDate(item.updatedAt),
        };
    };

    return (
        <WatchHistoryContext.Provider
            value={{
                history,
                historyMedia,
                isLoading,
                hasMore,
                loadMore,
                saveHistory,
                removeHistory,
                getHistoryItem,
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