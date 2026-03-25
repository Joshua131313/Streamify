import { createContext, useContext, useState, type Dispatch, type SetStateAction } from "react";
import type { INBAGame } from "../types/sports/nbaTypes";
import type { NHLGame } from "../types/sports/nhlTypes";
import { useNBAGames } from "../hooks/sportsHooks/useNBAGames";
import { useNHLGames } from "../hooks/sportsHooks/useNHLGames";
import { type GameProps } from "../types/sports/sportsTypes";
import { mapNBAToGameProps } from "../utils/sports/nbaUtils";
import { mapNHLToGameProps } from "../utils/sports/nhlUtils";


interface SportsContextType {
    nbaGames: GameProps[];
    nhlGames: GameProps[];
    todaysNHLGames: GameProps[];

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
                nbaGames: nbaGames.map(mapNBAToGameProps),
                nbaGamesError: nbaError,
                nbaGamesLoading,
                nhlGames: nhlGames.map(mapNHLToGameProps),
                nhlGamesError: nhlError, 
                nhlGamesLoading, 
                search,
                setSearch, 
                todaysNHLGames: todaysNHLGames.map(mapNHLToGameProps),
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