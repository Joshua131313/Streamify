import {
    createContext,
    useContext,
    useEffect,
    useRef,
    useState,
    type ReactNode,
} from "react";

import { useAuthProvider } from "./AuthContext";
import { useLocalStorage } from "../hooks/utilHooks/useLocalStorage";

import {
    collection,
    getDocs,
    addDoc,
    deleteDoc,
    doc,
    query,
    orderBy,
    Timestamp,
    onSnapshot,
} from "firebase/firestore";
import { db } from "../firebase/firebase";

export type SearchHistoryItem = {
    searchValue: string;
    timeStamp: Date;
    firebaseId?: string;
};

type ContextType = {
    history: SearchHistoryItem[];
    filteredHistory: SearchHistoryItem[];
    setSearchTerm: (term: string) => void;
    addSearch: (value: string) => Promise<void>;
    deleteSearch: (value: string) => Promise<void>;
    clearAll: () => Promise<void>;
};

const SearchHistoryContext = createContext<ContextType | null>(null);

export const SearchHistoryProvider = ({ children }: { children: ReactNode }) => {
    const { user } = useAuthProvider();
    const { get, set } = useLocalStorage();
    const [searchTerm, setSearchTerm] = useState("");
    const [history, setHistory] = useState<SearchHistoryItem[]>([]);
    const historyRef = useRef<SearchHistoryItem[]>([]);

    useEffect(() => {
        historyRef.current = history;
    }, [history]);


    useEffect(() => {
        if (!user?.uid) {
            setHistory(get("search-history", []));
            return;
        }

        const q = query(
            collection(db, "users", user.uid, "searchHistory"),
            orderBy("timeStamp", "desc")
        );

        const unsubscribe = onSnapshot(q, (snapshot) => {
            const data = snapshot.docs.map(docSnap => {
                const d = docSnap.data();

                return {
                    firebaseId: docSnap.id,
                    searchValue: d.searchValue,
                    timeStamp: (d.timeStamp as Timestamp).toDate(),
                };
            });

            setHistory(data);
        });

        return () => unsubscribe();
    }, [user?.uid]);

    const addSearch = async (value: string) => {
        const entry = {
            searchValue: value,
            timeStamp: new Date(),
        };

        if (user?.uid) {
            await addDoc(
                collection(db, "users", user.uid, "searchHistory"),
                {
                    ...entry,
                    timeStamp: Timestamp.fromDate(entry.timeStamp),
                }
            );
            return;
        }

        const filtered = historyRef.current.filter(h => h.searchValue !== value);
        const updated = [entry, ...filtered];

        set("search-history", updated);
        historyRef.current = updated;
        setHistory(updated);
    };

    const deleteSearch = async (value: string) => {
        if (user?.uid) {
            const existing = historyRef.current.find(
                h => h.searchValue === value
            );

            if (existing?.firebaseId) {
                await deleteDoc(
                    doc(db, "users", user.uid, "searchHistory", existing.firebaseId)
                );
            }

            return;
        }

        const updated = historyRef.current.filter(
            h => h.searchValue !== value
        );

        set("search-history", updated);
        historyRef.current = updated;
        setHistory(updated);
    };

    const clearAll = async () => {
        if (user?.uid) {
            const deletes = historyRef.current
                .filter(h => h.firebaseId)
                .map(h =>
                    deleteDoc(
                        doc(db, "users", user.uid!, "searchHistory", h.firebaseId!)
                    )
                );

            await Promise.all(deletes);

            setHistory([]);
            historyRef.current = [];
            return;
        }

        set("search-history", []);
        historyRef.current = [];
        setHistory([]);
    };
    const filteredHistory = history
        .filter(h =>
            h.searchValue.toLowerCase().includes(searchTerm.toLowerCase())
        )
        .slice(0, 10);
    return (
        <SearchHistoryContext.Provider
            value={{
                history,
                filteredHistory,
                setSearchTerm,
                addSearch,
                deleteSearch,
                clearAll
            }}
        >
            {children}
        </SearchHistoryContext.Provider>
    );
};

export const useSearchHistoryContext = () => {
    const ctx = useContext(SearchHistoryContext);
    if (!ctx) throw new Error("Must be used inside SearchHistoryProvider");
    return ctx;
};