import { createContext, useContext, useState } from "react";
import type { INBAGame } from "../types/sports/nbaTypes";
import type { NHLGame } from "../types/sports/nhlTypes";
import { useNBAGames } from "../hooks/sportsHooks/useNBAGames";
import { useNHLGames } from "../hooks/sportsHooks/useNHLGames";


interface SportsContextType {
    nbaGames: INBAGame[];
    nhlGames: NHLGame[];
    todaysNHLGames: NHLGame[];

    search: string;
    setSearch: (value: string) => void;

    nhlGamesLoading: boolean;
    nhlGamesError: unknown;

    nbaGamesLoading: boolean;
    nbaGamesError: unknown;
}
const SportsContext = createContext<SportsContextType | null>(null);

export const SportsProvider = ({ children } : { children: React.ReactNode}) => {
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

    return (
        <SportsContext.Provider
            value={{
                nbaGames,
                nbaGamesError: nbaError,
                nbaGamesLoading,
                nhlGames: todaysNHLGames,
                nhlGamesError: nhlError, 
                nhlGamesLoading, 
                search,
                setSearch, 
                todaysNHLGames
            }}
        >
            {children}
        </SportsContext.Provider>
    )
}

export const useSports = () => {
    const ctx = useContext(SportsContext);
    if(!ctx) {
        throw new Error("useSports must be used inside SportsProvider");
    }
    return ctx;
}