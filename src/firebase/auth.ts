import { doc, serverTimestamp, setDoc, collection, addDoc, updateDoc } from "firebase/firestore";
import { auth, db } from "./firebase";
import type { FavoriteTeamItem } from "../context/FavoriteTeamsContext";
import type { Leagues, TeamInfo } from "../types/sports/sportsTypes";
import { getTeamsMapFromLeague } from "../utils/sports/sportsUtils";
import { updateProfile } from "firebase/auth";

export const createUserDocument = async (
    uid: string,
    email: string | null,
    firstName?: string,
    lastName?: string,
    fullName?: string
) => {
    if (!firstName && !lastName && fullName) {
        const parts = fullName.split(" ");
        firstName = parts[0] || "";
        lastName = parts.slice(1).join(" ") || "";
    }

    const rawSearch = localStorage.getItem("search-history");
    const rawShows = localStorage.getItem("show-history");

    let searchHistory: any[] = [];
    let showHistory: any[] = [];

    try {
        searchHistory = rawSearch ? JSON.parse(rawSearch) : [];
        showHistory = rawShows ? JSON.parse(rawShows) : [];
    } catch {
        console.warn("Failed to parse localStorage");
    }
    
    await setDoc(
        doc(db, "users", uid),
        {
            userId: uid,
            email,
            firstName: firstName || "",
            lastName: lastName || "",
            onboardingComplete: false,
            createdAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
        },
        { merge: true }
    );
    
    if(auth.currentUser) {
        await updateProfile(auth.currentUser, {
            displayName: `${firstName || ""} ${lastName || ""}`.trim()
        })
    }

    await Promise.all(
        showHistory.map((item) => {
            const ref = doc(
                db,
                "users",
                uid,
                "showHistory",
                item.showId.toString()
            );

            return setDoc(
                ref,
                {
                    showId: item.showId,
                    season: Number(item.season),
                    episode: Number(item.episode),
                    updatedAt: item.updatedAt
                        ? new Date(item.updatedAt)
                        : serverTimestamp(),
                },
                { merge: true }
            );
        })
    );

    await Promise.all(
        searchHistory.map((item) => {
            const ref = collection(db, "users", uid, "searchHistory");

            return addDoc(ref, {
                searchValue: item.searchValue,
                timeStamp: item.timeStamp
                    ? new Date(item.timeStamp)
                    : serverTimestamp(),
            });
        })
    );
};
export const completeOnboarding = async () => {
    const user = auth.currentUser;

    if(user?.isAnonymous || !user) {
        throw new Error("user not authenticated");
    }
    const ref = doc(db, "users", user.uid);

    await updateDoc(ref, {
        onboardingComplete: true
    })
}
export const addFavoriteGenres = async (genreIds: string[]) => {
    const user = auth.currentUser;

    if(user?.isAnonymous || !user) {
        throw new Error("user not authenticated");
    }

    const ref = doc(db, "users", user.uid);

    await setDoc(ref, {
        favoriteGenres: genreIds
    }, {merge: true})
}

export const addTeamsToFavorites = async (teams: TeamInfo[]) => {
    const user = auth.currentUser;

    if(user?.isAnonymous || !user) {
        throw new Error("User not authenticated");
    }

    const ref = collection(db, "users", user.uid, "favoriteTeams");

    await Promise.all(
        teams.map(team => {
                const teamInfo: FavoriteTeamItem = {
                    abbrev: team?.abbreviation,
                    league: team.league,
                    name: team?.teamName,
                    firebaseId: `temp-${team?.abbreviation}`,
                    timeStamp: serverTimestamp()
                }
                return addDoc(ref,  teamInfo)
            
        })
    )
}