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
    onSnapshot,
    addDoc,
    deleteDoc,
    doc,
} from "firebase/firestore";


import type { TMDBMedia } from "../types/TMDBMediaType";
import { db } from "../firebase/firebase";
import { useLocalStorage } from "../hooks/utilHooks/useLocalStorage";
import { useAuthProvider } from "./AuthContext";
import { useTMDBByIds } from "../hooks/mediaHooks/tmdbHooks/useTMDBByIds";

type SavedMediaRef = {
    mediaId: number;
    mediaType: "movie" | "tv";
    firebaseId?: string;
};

type ContextType = {
    savedMedia: TMDBMedia[];
    isLoading: boolean;
    addMedia: (media: TMDBMedia) => Promise<void>;
    removeMedia: (media: TMDBMedia) => Promise<void>;
    isSaved: (media: TMDBMedia) => boolean;
};

const SavedMediaContext = createContext<ContextType | null>(null);

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

export const SavedMediaProvider = ({ children }: { children: ReactNode }) => {
    const { user } = useAuthProvider();
    const { get, set } = useLocalStorage();

    const [savedRefs, setSavedRefs] = useState<SavedMediaRef[]>([]);
    const savedRef = useRef<SavedMediaRef[]>([]);

    useEffect(() => {
        savedRef.current = savedRefs;
    }, [savedRefs]);

    useEffect(() => {
        if (!user?.uid) {
            setSavedRefs(get("savedMedia", []));
            return;
        }

        const unsubscribe = onSnapshot(
            collection(db, "users", user.uid, "savedMedia"),
            (snapshot) => {
                const data = snapshot.docs.map(docSnap => ({
                    firebaseId: docSnap.id,
                    ...(docSnap.data() as Omit<SavedMediaRef, "firebaseId">),
                }));

                setSavedRefs(data);
            }
        );

        return () => unsubscribe();
    }, [user?.uid]);


    const { media: savedMedia, isLoading } = useTMDBByIds(
        savedRefs.map(r => ({
            mediaId: r.mediaId,
            mediaType: r.mediaType
        }))
    );

    const addMedia = async (media: TMDBMedia) => {
        if (savedRef.current.some(m => m.mediaId === media.id)) return;

        const refData: SavedMediaRef = {
            mediaId: media.id,
            mediaType: media.mediaType,
            firebaseId: `temp-${media.id}`
        };

        setSavedRefs(prev => [refData, ...prev]);
        savedRef.current = [refData, ...savedRef.current];

        if (user?.uid) {
            try {
                await addDoc(
                    collection(db, "users", user.uid, "savedMedia"),
                    {
                        mediaId: media.id,
                        mediaType: media.mediaType
                    }
                );
            } catch {
                setSavedRefs(prev => prev.filter(m => m.mediaId !== media.id));
                savedRef.current = savedRef.current.filter(m => m.mediaId !== media.id);
            }
            return;
        }

        const updated = [refData, ...savedRef.current];
        set("savedMedia", updated);
        savedRef.current = updated;
        setSavedRefs(updated);
    };

    const removeMedia = async (media: TMDBMedia) => {
        const existing = savedRef.current.find(m => m.mediaId === media.id);

        setSavedRefs(prev => prev.filter(m => m.mediaId !== media.id));
        savedRef.current = savedRef.current.filter(m => m.mediaId !== media.id);

        if (user?.uid && existing?.firebaseId) {
            await deleteDoc(
                doc(
                    db,
                    "users",
                    user.uid,
                    "savedMedia",
                    existing.firebaseId
                )
            );
            return;
        }

        const updated = savedRef.current.filter(m => m.mediaId !== media.id);
        set("savedMedia", updated);
        savedRef.current = updated;
        setSavedRefs(updated);
    };

    const isSaved = (media: TMDBMedia) => {
        return savedRef.current.some(m => m.mediaId === media.id);
    };

    return (
        <SavedMediaContext.Provider
            value={{ savedMedia, isLoading, addMedia, removeMedia, isSaved }}
        >
            {children}
        </SavedMediaContext.Provider>
    );
};

export const useSavedMediaContext = () => {
    const ctx = useContext(SavedMediaContext);
    if (!ctx) throw new Error("Must be used inside SavedMediaProvider");
    return ctx;
};