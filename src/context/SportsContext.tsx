import { createContext, useContext, useEffect, useMemo, useState } from "react";
import { useNBAGames } from "../hooks/sportsHooks/useNBAGames";
import { useNHLGames } from "../hooks/sportsHooks/useNHLGames";
import { useMLBGames } from "../hooks/sportsHooks/useMLBGames";
import { mapNBAToGameProps } from "../utils/sports/nbaUtils";
import { mapNHLToGameProps } from "../utils/sports/nhlUtils";
import { mapMLBToGameProps } from "../utils/sports/mlbUtils";
import { filterGames, getPriority } from "../utils/sports/sportsUtils";
import { useFavoriteTeamsContext } from "./FavoriteTeamsContext";
import type { GameProps } from "../types/sports/sportsTypes";
import { SportsPlayer } from "../pages/Sports/SportsPlayer";
import { useLocation } from "react-router-dom";

export type SportFilterType = "status" | "league" | "sport";
export type SportFilter = {
    label: string;
    value: string;
    type: SportFilterType;
};
export type SportsCardsLayout = "slider" | "grid" | "list";

export const quickFilters: SportFilter[] = [
    { label: "Live", value: "LIVE", type: "status" },
    { label: "Pre Game", value: "PRE", type: "status" },
    { label: "Upcoming", value: "FUT", type: "status" },
    { label: "Finished", value: "FINAL", type: "status" },

    { label: "NBA", value: "NBA", type: "league" },
    { label: "NHL", value: "NHL", type: "league" },
    { label: "MLB", value: "MLB", type: "league" },

    { label: "TV", value: "TV", type: "league" }
];

interface SportsContextType {
    nbaGames: GameProps[];
    nhlGames: GameProps[];
    mlbGames: GameProps[];
    allOfTodaysGames: GameProps[];
    nbaGamesLoading: boolean;
    nhlGamesLoading: boolean;
    mlbGamesLoading: boolean;

    search: string;
    setSearch: (value: string) => void;

    filters: SportFilter[];
    setFilters: React.Dispatch<React.SetStateAction<SportFilter[]>>;
    addSportFilter: (filter: SportFilter) => void;

    nbaGameCards: GameProps[];
    nhlGameCards: GameProps[];
    mlbGameCards: GameProps[];
    favoriteNBAGameCards: GameProps[];
    favoriteNHLGameCards: GameProps[];
    favoriteMLBGameCards: GameProps[];
    favoriteGameCards: GameProps[];

    layout: SportsCardsLayout;
    setLayout: React.Dispatch<React.SetStateAction<SportsCardsLayout>>;
}

const SportsContext = createContext<SportsContextType | null>(null);

export const SportsProvider = ({ children }: { children: React.ReactNode }) => {
    const [search, setSearch] = useState("");
    const [filters, setFilters] = useState<SportFilter[]>([]);
    const [layout, setLayout] = useState<SportsCardsLayout>("slider");
    const { favoriteTeams } = useFavoriteTeamsContext();
    const location = useLocation()
    const { nbaGames, nbaGamesLoading } = useNBAGames();
    const { games: nhlGames, isLoading: nhlGamesLoading } = useNHLGames();
    const { games: mlbGames, isLoading: mlbGamesLoading } = useMLBGames();
    
    const mappedNBAGames = nbaGames.map(mapNBAToGameProps);
    const mappedNHLGames = nhlGames.map(mapNHLToGameProps);
    const mappedMLBGames = mlbGames.map(mapMLBToGameProps);

    const addSportFilter = (filter: SportFilter) => {
        setFilters(prev =>
            prev.some(f => f.value === filter.value)
                ? prev.filter(f => f.value !== filter.value)
                : [...prev, filter]
        );
    };

    const nbaGameCards = useMemo(() => {
        return filterGames(mappedNBAGames, search, filters);
    }, [mappedNBAGames, search, filters]);

    const nhlGameCards = useMemo(() => {
        return filterGames(mappedNHLGames, search, filters);
    }, [mappedNHLGames, search, filters]);

    const mlbGameCards = useMemo(() => {
        return filterGames(mappedMLBGames, search, filters);
    }, [mappedMLBGames, search, filters]);

    const allOfTodaysGames = [
        ...mappedNBAGames,
        ...mappedNHLGames,
        ...mappedMLBGames
    ];
    const favSet = useMemo(
        () => new Set(favoriteTeams.map(t => t.name)),
        [favoriteTeams]
    );

    const favoriteNBAGameCards = useMemo(() => {
        return nbaGameCards.filter(
            game =>
                favSet.has(game.awayTeam.name) ||
                favSet.has(game.homeTeam.name)
        );
    }, [nbaGameCards, favSet]);

    const favoriteNHLGameCards = useMemo(() => {
        return nhlGameCards.filter(
            game =>
                favSet.has(game.awayTeam.name) ||
                favSet.has(game.homeTeam.name)
        );
    }, [nhlGameCards, favSet]);

    const favoriteMLBGameCards = useMemo(() => {
        return mlbGameCards.filter(
            game =>
                favSet.has(game.awayTeam.name) ||
                favSet.has(game.homeTeam.name)
        );
    }, [mlbGameCards, favSet]);

    const favoriteGameCards = useMemo(() => {
        return filterGames([
            ...favoriteNBAGameCards,
            ...favoriteNHLGameCards,
            ...favoriteMLBGameCards
        ], search, filters);
    }, [favoriteNBAGameCards, favoriteNHLGameCards, favoriteMLBGameCards, search, filters]);

    useEffect(() => {
        setFilters([]);
        console.log(location.pathname)
        // if(location.pathname.includes("nba") || location.pathname.includes("nhl") || location.pathname.includes("mlb")) {
        //     setLayout("list")
        // }
        // else {
        //     setLayout("slider")
        // }
    }, [location])

    return (
        <SportsContext.Provider
            value={{
                nbaGames: mappedNBAGames,
                nhlGames: mappedNHLGames,
                mlbGames: mappedMLBGames,
                allOfTodaysGames,
                nbaGamesLoading,
                nhlGamesLoading,
                mlbGamesLoading,

                search,
                setSearch,

                filters,
                setFilters,
                addSportFilter,

                nbaGameCards,
                favoriteNBAGameCards,
                nhlGameCards,
                favoriteNHLGameCards,
                mlbGameCards,
                favoriteMLBGameCards,

                favoriteGameCards,

                layout,
                setLayout
            }}
        >
            {children}
        </SportsContext.Provider>
    );
};

export const useSports = () => {
    const ctx = useContext(SportsContext);
    if (!ctx) throw new Error("useSports must be used inside SportsProvider");
    return ctx;
};