import { useEffect, useState } from "react";
import { useAuthProvider } from "../../context/AuthContext";
import { db } from "../../firebase/firebase";
import {
    collection,
    onSnapshot,
    addDoc,
    deleteDoc,
    doc,
    query
} from "firebase/firestore";
import { useLocalStorage } from "../utilHooks/useLocalStorage";
import type { TMDBMedia } from "../../types/TMDBMediaType";
import { cleanFirestoreData } from "../../utils/helpers";

type SavedMediaDoc = TMDBMedia & {
    firebaseId?: string;
};

export const useSavedMedia = () => {
    const { user } = useAuthProvider();
    const { get, append, remove } = useLocalStorage();

    const [savedMedia, setSavedMedia] = useState<SavedMediaDoc[]>([]);

    useEffect(() => {
        if (user?.uid) {
            const q = query(collection(db, "users", user.uid, "savedMedia"));

            const unsubscribe = onSnapshot(q, (snapshot) => {
                const data: SavedMediaDoc[] = snapshot.docs.map(docSnap => ({
                    firebaseId: docSnap.id, 
                    ...(docSnap.data() as TMDBMedia)
                }));

                setSavedMedia(data);
            });

            return () => unsubscribe();
        } else {
            const local = get<TMDBMedia[]>("savedMedia", []);

            setSavedMedia(
                local.map(m => ({
                    ...m,
                    firebaseId: undefined
                }))
            );
        }
    }, [user]);

    const addMedia = async (media: TMDBMedia) => {
        if (savedMedia.some(m => m.id === media.id)) return;

        if (user?.uid) {
            await addDoc(
                collection(db, "users", user.uid, "savedMedia"),
                cleanFirestoreData(media)
            );
        } else {
            append("savedMedia", media);
            setSavedMedia(prev => [...prev, media]);
        }
    };

    const removeMedia = async (media: TMDBMedia) => {
        if (user?.uid) {
            const existing = savedMedia.find(m => m.id === media.id);

            if (existing?.firebaseId) {
                await deleteDoc(
                    doc(db, "users", user.uid, "savedMedia", existing.firebaseId)
                );
            }
        } else {
            remove<TMDBMedia>("savedMedia", m => m.id === media.id);

            setSavedMedia(prev => prev.filter(m => m.id !== media.id));
        }
    };

    const isSaved = (media: TMDBMedia) => {
        return savedMedia.some(m => m.id === media.id);
    };

    return {
        savedMedia,
        addMedia,
        removeMedia,
        isSaved
    };
};