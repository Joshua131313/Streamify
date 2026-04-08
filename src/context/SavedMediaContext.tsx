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
import { cleanFirestoreData } from "../utils/helpers";

type SavedMediaItem = TMDBMedia & {
    firebaseId?: string;
};

type ContextType = {
    savedMedia: SavedMediaItem[];
    addMedia: (media: TMDBMedia) => Promise<void>;
    removeMedia: (media: TMDBMedia) => Promise<void>;
    isSaved: (media: TMDBMedia) => boolean;
};

const SavedMediaContext = createContext<ContextType | null>(null);

export const SavedMediaProvider = ({ children }: { children: ReactNode }) => {
    const { user } = useAuthProvider();
    const { get, set } = useLocalStorage();

    const [savedMedia, setSavedMedia] = useState<SavedMediaItem[]>([]);
    const savedRef = useRef<SavedMediaItem[]>([]);

    useEffect(() => {
        savedRef.current = savedMedia;
    }, [savedMedia]);

    useEffect(() => {
        if (!user?.uid) {
            setSavedMedia(get("savedMedia", []));
            return;
        }

        const unsubscribe = onSnapshot(
            collection(db, "users", user.uid, "savedMedia"),
            (snapshot) => {
                const data = snapshot.docs.map(docSnap => ({
                    firebaseId: docSnap.id,
                    ...(docSnap.data() as TMDBMedia),
                }));

                setSavedMedia(data);
            }
        );

        return () => unsubscribe();
    }, [user?.uid]);

    const addMedia = async (media: TMDBMedia) => {
        if (savedRef.current.some(m => m.id === media.id)) return;

        const tempItem: SavedMediaItem = {
            ...media,
            firebaseId: `temp-${media.id}`,
        };

        setSavedMedia(prev => [tempItem, ...prev]);
        savedRef.current = [tempItem, ...savedRef.current];

        if (user?.uid) {
            try {
                await addDoc(
                    collection(db, "users", user.uid, "savedMedia"),
                    cleanFirestoreData(media)
                );
            } catch (err) {
                setSavedMedia(prev => prev.filter(m => m.id !== media.id));
                savedRef.current = savedRef.current.filter(m => m.id !== media.id);
            }
            return;
        }

        const updated = [media, ...savedRef.current];
        set("savedMedia", updated);
        savedRef.current = updated;
        setSavedMedia(updated);
    };

    const removeMedia = async (media: TMDBMedia) => {
        if (user?.uid) {
            const existing = savedRef.current.find(
                m => m.id === media.id
            );

            setSavedMedia(prev => prev.filter(m => m.id !== media.id));
            savedRef.current = savedRef.current.filter(m => m.id !== media.id);

            if (existing?.firebaseId) {
                await deleteDoc(
                    doc(
                        db,
                        "users",
                        user.uid,
                        "savedMedia",
                        existing.firebaseId
                    )
                );
            }

            return;
        }

        const updated = savedRef.current.filter(m => m.id !== media.id);
        set("savedMedia", updated);
        savedRef.current = updated;
        setSavedMedia(updated);
    };

    const isSaved = (media: TMDBMedia) => {
        return savedRef.current.some(m => m.id === media.id);
    };

    return (
        <SavedMediaContext.Provider
            value={{ savedMedia, addMedia, removeMedia, isSaved }}
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