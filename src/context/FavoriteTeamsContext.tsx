import {
    createContext,
    useContext,
    useEffect,
    useRef,
    useState,
    useMemo,
    type ReactNode,
} from "react";

import {
    collection,
    onSnapshot,
    addDoc,
    deleteDoc,
    doc,
    serverTimestamp,
    FieldValue,
} from "firebase/firestore";

import { auth, db } from "../firebase/firebase";
import { useLocalStorage } from "../hooks/utilHooks/useLocalStorage";
import { useAuthProvider } from "./AuthContext";
import { cleanFirestoreData } from "../utils/helpers";
import type { GameTeam, Leagues, TeamAbbrevs } from "../types/sports/sportsTypes";

export interface FavoriteTeamItem  {
    abbrev: TeamAbbrevs,
    league: Leagues,
    name: string,
    timeStamp?: FieldValue;
    firebaseId?: string,
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

    // 🔥 Load teams
    useEffect(() => {
    if (!user?.uid || auth.currentUser?.isAnonymous) {
            const local = get("favoriteTeams", []);
            setFavoriteTeams(local);
            teamsRef.current = local;
            return;
        }

        const unsubscribe = onSnapshot(
            collection(db, "users", user.uid, "favoriteTeams"),
            (snapshot) => {
                const data = snapshot.docs.map(docSnap => ({
                    firebaseId: docSnap.id,
                    ...(docSnap.data() as FavoriteTeamItem),
                }));

                setFavoriteTeams(data);
            }
        );

        return () => unsubscribe();
    }, [user?.uid]);

    // 🔥 ADD TEAM
    const addTeam = async (team: GameTeam) => {
        if (teamsRef.current.some(t => t.abbrev === team.abbrev)) return;

        // LOCAL MODE
        if (!user?.uid || auth.currentUser?.isAnonymous) {
            const updated : FavoriteTeamItem[] = [{abbrev: team.abbrev, league: team.league, name: team.name, timeStamp: serverTimestamp()}, ...teamsRef.current];

            teamsRef.current = updated;
            setFavoriteTeams(updated);
            set("favoriteTeams", updated);

            return;
        }

        // FIREBASE MODE (optimistic)
        const tempItem: FavoriteTeamItem = {
            abbrev: team.abbrev,
            league: team.league,
            name: team.name,
            firebaseId: `temp-${team.abbrev}`,
            timeStamp: serverTimestamp()
        };

        setFavoriteTeams(prev => [tempItem, ...prev]);
        teamsRef.current = [tempItem, ...teamsRef.current];

        try {
            await addDoc(
                collection(db, "users", user.uid, "favoriteTeams"),
                cleanFirestoreData(team)
            );
        } catch {
            // rollback
            setFavoriteTeams(prev =>
                prev.filter(t => t.abbrev !== team.abbrev)
            );
            teamsRef.current = teamsRef.current.filter(
                t => t.abbrev !== team.abbrev
            );
        }
    };

    const removeTeam = async (team: GameTeam) => {
        if (!user?.uid || auth.currentUser?.isAnonymous) {
            const updated = teamsRef.current.filter(
                t => t.abbrev !== team.abbrev
            );

            teamsRef.current = updated;
            setFavoriteTeams(updated);
            set("favoriteTeams", updated);

            return;
        }

        const existing = teamsRef.current.find(
            t => t.abbrev === team.abbrev
        );

        setFavoriteTeams(prev =>
            prev.filter(t => t.abbrev !== team.abbrev)
        );
        teamsRef.current = teamsRef.current.filter(
            t => t.abbrev !== team.abbrev
        );

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
    };

    const isFavorite = (team: GameTeam) => {
        return teamsRef.current.some(
            t => t.abbrev === team.abbrev
        );
    };

    const value = useMemo(() => ({
        favoriteTeams,
        addTeam,
        removeTeam,
        isFavorite
    }), [favoriteTeams]);

    return (
        <FavoriteTeamsContext.Provider value={value}>
            {children}
        </FavoriteTeamsContext.Provider>
    );
};

export const useFavoriteTeamsContext = () => {
    const ctx = useContext(FavoriteTeamsContext);
    if (!ctx) throw new Error("Must be used inside FavoriteTeamsProvider");
    return ctx;
};