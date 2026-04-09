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

import { db } from "../firebase/firebase";
import { useLocalStorage } from "../hooks/utilHooks/useLocalStorage";
import { useAuthProvider } from "./AuthContext";
import { cleanFirestoreData } from "../utils/helpers";
import type { GameTeam } from "../types/sports/sportsTypes";


type FavoriteTeamItem = GameTeam & {
    firebaseId?: string;
};

type ContextType = {
    favoriteTeams: FavoriteTeamItem[];
    addTeam: (team: GameTeam) => Promise<void>;
    removeTeam: (team: GameTeam) => Promise<void>;
    isFavorite: (team: GameTeam) => boolean;
};

const FavoriteTeamsContext = createContext<ContextType | null>(null);

export const FavoriteTeamsProvider = ({ children }: { children: ReactNode }) => {
    const { user } = useAuthProvider();
    const { get, set } = useLocalStorage();

    const [favoriteTeams, setFavoriteTeams] = useState<FavoriteTeamItem[]>([]);
    const teamsRef = useRef<FavoriteTeamItem[]>([]);

    useEffect(() => {
        teamsRef.current = favoriteTeams;
    }, [favoriteTeams]);

    useEffect(() => {
        if (!user?.uid) {
            setFavoriteTeams(get("favoriteTeams", []));
            return;
        }

        const unsubscribe = onSnapshot(
            collection(db, "users", user.uid, "favoriteTeams"),
            (snapshot) => {
                const data = snapshot.docs.map(docSnap => ({
                    firebaseId: docSnap.id,
                    ...(docSnap.data() as GameTeam),
                }));

                setFavoriteTeams(data);
            }
        );

        return () => unsubscribe();
    }, [user?.uid]);

    const addTeam = async (team: GameTeam) => {
        if (teamsRef.current.some(t => t.abbrev === team.abbrev)) return;

        const tempItem: FavoriteTeamItem = {
            ...team,
            firebaseId: `temp-${team.abbrev}`,
        };

        setFavoriteTeams(prev => [tempItem, ...prev]);
        teamsRef.current = [tempItem, ...teamsRef.current];

        if (user?.uid) {
            try {
                await addDoc(
                    collection(db, "users", user.uid, "favoriteTeams"),
                    cleanFirestoreData(team)
                );
            } catch {
                // rollback
                setFavoriteTeams(prev => prev.filter(t => t.abbrev !== team.abbrev));
                teamsRef.current = teamsRef.current.filter(t => t.abbrev !== team.abbrev);
            }
            return;
        }

        const updated = [team, ...teamsRef.current];
        set("favoriteTeams", updated);
        teamsRef.current = updated;
        setFavoriteTeams(updated);
    };

    const removeTeam = async (team: GameTeam) => {
        if (user?.uid) {
            const existing = teamsRef.current.find(t => t.abbrev === team.abbrev);

            setFavoriteTeams(prev => prev.filter(t => t.abbrev !== team.abbrev));
            teamsRef.current = teamsRef.current.filter(t => t.abbrev !== team.abbrev);

            if (existing?.firebaseId) {
                await deleteDoc(
                    doc(
                        db,
                        "users",
                        user.uid,
                        "favoriteTeams",
                        existing.firebaseId
                    )
                );
            }

            return;
        }

        const updated = teamsRef.current.filter(t => t.abbrev !== team.abbrev);
        set("favoriteTeams", updated);
        teamsRef.current = updated;
        setFavoriteTeams(updated);
    };

    const isFavorite = (team: GameTeam) => {
        return teamsRef.current.some(t => t.abbrev === team.abbrev);
    };

    return (
        <FavoriteTeamsContext.Provider
            value={{ favoriteTeams, addTeam, removeTeam, isFavorite }}
        >
            {children}
        </FavoriteTeamsContext.Provider>
    );
};

export const useFavoriteTeamsContext = () => {
    const ctx = useContext(FavoriteTeamsContext);
    if (!ctx) throw new Error("Must be used inside FavoriteTeamsProvider");
    return ctx;
};