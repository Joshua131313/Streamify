import { createContext, useContext, useState } from "react";
import type { INBAGame } from "../types/sports/nbaTypes";
import type { NHLGame } from "../types/sports/nhlTypes";
import { useNBAGames } from "../hooks/sportsHooks/useNBAGames";
import { useNHLGames } from "../hooks/sportsHooks/useNHLGames";
import { type GameProps, type Leagues } from "../types/sports/sportsTypes";
import { mapNBAToGameProps } from "../utils/sports/nbaUtils";
import { mapNHLToGameProps } from "../utils/sports/nhlUtils";

interface SportsContextType {
    nbaGames: GameProps[];
    nhlGames: GameProps[];
    todaysNHLGames: GameProps[];
    allOfTodaysGames: GameProps[];

    search: string;
    setSearch: (value: string) => void;

    nhlGamesLoading: boolean;
    nhlGamesError: unknown;

    nbaGamesLoading: boolean;
    nbaGamesError: unknown;

    // 🔥 NEW
    getGameById: (league: Leagues, id: string) => GameProps | undefined;
}

const SportsContext = createContext<SportsContextType | null>(null);

export const SportsProvider = ({ children }: { children: React.ReactNode }) => {
    const [search, setSearch] = useState("");

    const {
        nbaGames,
        error: nbaError,
        nbaGamesLoading
    } = useNBAGames();

    const {
        games: nhlGames,
        todaysGames: todaysNHLGames,
        isLoading: nhlGamesLoading,
        error: nhlError
    } = useNHLGames();

    const mappedNBAGames = nbaGames.map(mapNBAToGameProps);
    const mappedNHLGames = nhlGames.map(mapNHLToGameProps);
    const mappedTodaysNHLGames = todaysNHLGames.map(mapNHLToGameProps);

    const allOfTodaysGames = [
        ...mappedNBAGames,
        ...mappedTodaysNHLGames
    ];

    // 🔥 CENTRALIZED GAME LOOKUP
    const getGameById = (league: Leagues, id: string) => {
        if (league === "NBA") {
            return mappedNBAGames.find(g => g.id == id);
        }

        if (league === "NHL") {
            console.log(mappedNHLGames)
            return mappedNHLGames.find(g => g.id == id);
        }

        return undefined;
    };

    return (
        <SportsContext.Provider
            value={{
                nbaGames: mappedNBAGames,
                nbaGamesError: nbaError,
                nbaGamesLoading,

                nhlGames: mappedNHLGames,
                nhlGamesError: nhlError,
                nhlGamesLoading,

                todaysNHLGames: mappedTodaysNHLGames,
                allOfTodaysGames,

                search,
                setSearch,

                getGameById // ✅ exposed
            }}
        >
            {children}
        </SportsContext.Provider>
    );
};

export const useSports = () => {
    const ctx = useContext(SportsContext);
    if (!ctx) {
        throw new Error("useSports must be used inside SportsProvider");
    }
    return ctx;
};