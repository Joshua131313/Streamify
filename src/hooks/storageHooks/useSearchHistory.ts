import { useEffect, useState, useMemo } from "react";
import { type SearchMediaHistory } from "../../types/storage";
import { useAuthProvider } from "../../context/AuthContext";
import { HISTORY_KEY } from "../../data/localStorageKeys";
import {
    collection,
    onSnapshot,
    query,
    orderBy,
    Timestamp,
    addDoc,
    deleteDoc,
    doc
} from "firebase/firestore";
import { db } from "../../firebase/firebase";

export const useSearchHistory = () => {
    const { user } = useAuthProvider();
    const [history, setHistory] = useState<(SearchMediaHistory & { id?: string })[]>([]);
    const [searchTerm, setSearchTerm] = useState("");

    useEffect(() => {
        if (user?.uid) {
            const q = query(
                collection(db, "users", user.uid, "searchHistory"),
                orderBy("timeStamp", "desc")
            );

            const unsubscribe = onSnapshot(q, (snapshot) => {
                const newHistory = snapshot.docs.map(docSnap => {
                    const data = docSnap.data();

                    return {
                        id: docSnap.id,
                        searchValue: data.searchValue,
                        timeStamp: (data.timeStamp as Timestamp).toDate()
                    };
                });

                setHistory(newHistory);
            });

            return () => unsubscribe();
        } else {
            const saved = localStorage.getItem(HISTORY_KEY);
            if (saved) {
                setHistory(JSON.parse(saved));
            }
        }
    }, [user]);

    const filteredHistory = useMemo(() => {
        let result = history;

        if (searchTerm.trim()) {
            result = result.filter(h =>
                h.searchValue.toLowerCase().includes(searchTerm.toLowerCase())
            );
        }

        return result.slice(0, 10); 
    }, [history, searchTerm]);

    const addSearch = async (value: string) => {
        const entry: SearchMediaHistory = {
            searchValue: value,
            timeStamp: new Date()
        };

        if (user?.uid) {
            await addDoc(
                collection(db, "users", user.uid, "searchHistory"),
                {
                    searchValue: value,
                    timeStamp: Timestamp.fromDate(entry.timeStamp)
                }
            );
        } else {
            let local = history.filter(h => h.searchValue !== value);
            local.unshift(entry);

            localStorage.setItem(HISTORY_KEY, JSON.stringify(local));
            setHistory(local);
        }
    };

    const deleteSearch = async (id?: string, value?: string) => {
        if (user?.uid && id) {
            await deleteDoc(doc(db, "users", user.uid, "searchHistory", id));
        } else {
            const updated = history.filter(h => h.searchValue !== value);
            localStorage.setItem(HISTORY_KEY, JSON.stringify(updated));
            setHistory(updated);
        }
    };

    const clearAll = async () => {
        if (user?.uid) {
            const deletes = history.map(item =>
                item.id
                    ? deleteDoc(doc(db, "users", user.uid!, "searchHistory", item.id))
                    : Promise.resolve()
            );

            await Promise.all(deletes);
        } else {
            localStorage.removeItem(HISTORY_KEY);
            setHistory([]);
        }
    };

    return {
        history,            
        filteredHistory,      
        setSearchTerm,     
        addSearch,
        deleteSearch,
        clearAll
    };
};