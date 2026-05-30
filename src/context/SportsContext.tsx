import { createContext, useContext, useEffect, useMemo, useState } from "react";
import { useLocation } from "react-router-dom";

import { useNBAGames } from "../hooks/sportsHooks/useNBAGames";
import { useNHLGames } from "../hooks/sportsHooks/useNHLGames";
import { useMLBGames } from "../hooks/sportsHooks/useMLBGames";
import { useFavoriteTeamsContext } from "./FavoriteTeamsContext";

import type { SportDisplayGame } from "../types/sports/sportsDisplayTypes";

import {
    createNBADisplayGame,
    createNHLDisplayGame,
    createMLBDisplayGame,
    filterDisplayGames,
    isFavoriteDisplayGame,
    createWNBADisplayGame,
} from "../utils/sports/sportDisplayUtils";
import { useWNBAGames } from "../hooks/sportsHooks/useWNBAGames";
import type { Leagues } from "../types/sports/sportsTypes";

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
    { label: "WNBA", value: "WNBA", type: "league" },
    { label: "NHL", value: "NHL", type: "league" },
    { label: "MLB", value: "MLB", type: "league" },

    { label: "TV", value: "TV", type: "league" },
];

interface SportsContextType {
    nbaGames: SportDisplayGame[];
    wnbaGames: SportDisplayGame[];
    nhlGames: SportDisplayGame[];
    mlbGames: SportDisplayGame[];

    allOfTodaysGames: SportDisplayGame[];
    liveGames: SportDisplayGame[];

    nbaGamesLoading: boolean;
    wnbaGamesLoading: boolean;
    nhlGamesLoading: boolean;
    mlbGamesLoading: boolean;

    search: string;
    setSearch: (value: string) => void;

    filters: SportFilter[];
    setFilters: React.Dispatch<React.SetStateAction<SportFilter[]>>;
    addSportFilter: (filter: SportFilter) => void;
    
    getGame: (league: Leagues, gameId: string) => SportDisplayGame | undefined;

    nbaGameCards: SportDisplayGame[];
    wnbaGameCards: SportDisplayGame[];
    nhlGameCards: SportDisplayGame[];
    mlbGameCards: SportDisplayGame[];

    favoriteNBAGameCards: SportDisplayGame[];
    favoriteWNBAGameCards: SportDisplayGame[];
    favoriteNHLGameCards: SportDisplayGame[];
    favoriteMLBGameCards: SportDisplayGame[];
    favoriteGameCards: SportDisplayGame[];

    layout: SportsCardsLayout;
    setLayout: React.Dispatch<React.SetStateAction<SportsCardsLayout>>;
}

const SportsContext =
    createContext<SportsContextType | null>(null);

export const SportsProvider = ({
    children,
}: {
    children: React.ReactNode;
}) => {
    const [search, setSearch] =
        useState("");

    const [filters, setFilters] =
        useState<SportFilter[]>([]);

    const [layout, setLayout] =
        useState<SportsCardsLayout>("slider");

    const { favoriteTeams } =
        useFavoriteTeamsContext();

    const location =
        useLocation();

    const {
        nbaGames,
        nbaGamesLoading,
    } = useNBAGames();

    const {
        wnbaGames,
        wnbaGamesLoading,
    } = useWNBAGames();

    const {
        games: nhlGames,
        isLoading: nhlGamesLoading,
    } = useNHLGames();

    const {
        games: mlbGames,
        isLoading: mlbGamesLoading,
    } = useMLBGames();

    const mappedNBAGames =
        useMemo(() => {
            return nbaGames.map(createNBADisplayGame);
        }, [nbaGames]);
    const mappedWNBAGames =
        useMemo(() => {
            return wnbaGames.map(createWNBADisplayGame);
        }, [wnbaGames]);

    const mappedNHLGames =
        useMemo(() => {
            return nhlGames.map(createNHLDisplayGame);
        }, [nhlGames]);

    const mappedMLBGames =
        useMemo(() => {
            return mlbGames.map(createMLBDisplayGame);
        }, [mlbGames]);

    const addSportFilter = (
        filter: SportFilter
    ) => {
        setFilters(prev =>
            prev.some(f => f.value === filter.value)
                ? prev.filter(f => f.value !== filter.value)
                : [...prev, filter]
        );
    };

    const nbaGameCards =
        useMemo(() => {
            return filterDisplayGames(
                mappedNBAGames,
                search,
                filters
            );
        }, [mappedNBAGames, search, filters]);

    const wnbaGameCards =
        useMemo(() => {
            return filterDisplayGames(
                mappedWNBAGames,
                search,
                filters
            );
        }, [mappedWNBAGames, search, filters]);

    const nhlGameCards =
        useMemo(() => {
            return filterDisplayGames(
                mappedNHLGames,
                search,
                filters
            );
        }, [mappedNHLGames, search, filters]);

    const mlbGameCards =
        useMemo(() => {
            return filterDisplayGames(
                mappedMLBGames,
                search,
                filters
            );
        }, [mappedMLBGames, search, filters]);

    const allOfTodaysGames =
        useMemo(() => {
            return [
                ...mappedNBAGames,
                ...mappedWNBAGames,
                ...mappedNHLGames,
                ...mappedMLBGames,
            ];
        }, [
            mappedNBAGames,
            mappedWNBAGames,
            mappedNHLGames,
            mappedMLBGames,
        ]);

    const liveGames =
        useMemo(() => {
            return allOfTodaysGames.filter(game =>
                game.card.status === "LIVE" ||
                game.card.status === "HALFTIME"
            );
        }, [allOfTodaysGames]);

    const getGame = (league: Leagues, gameId: string) => {
        return allOfTodaysGames.find(x => x.league.toLowerCase() == league && x.id == gameId);
    }

    const favSet =
        useMemo(() => {
            return new Set(
                favoriteTeams.map(team => team.name)
            );
        }, [favoriteTeams]);

    const favoriteNBAGameCards =
        useMemo(() => {
            return nbaGameCards.filter(game =>
                isFavoriteDisplayGame(game, favSet)
            );
        }, [nbaGameCards, favSet]);

    const favoriteWNBAGameCards =
        useMemo(() => {
            return wnbaGameCards.filter(game =>
                isFavoriteDisplayGame(game, favSet)
            );
        }, [wnbaGameCards, favSet]);

    const favoriteNHLGameCards =
        useMemo(() => {
            return nhlGameCards.filter(game =>
                isFavoriteDisplayGame(game, favSet)
            );
        }, [nhlGameCards, favSet]);

    const favoriteMLBGameCards =
        useMemo(() => {
            return mlbGameCards.filter(game =>
                isFavoriteDisplayGame(game, favSet)
            );
        }, [mlbGameCards, favSet]);

    const favoriteGameCards =
        useMemo(() => {
            return filterDisplayGames(
                [
                    ...favoriteNBAGameCards,
                    ...favoriteWNBAGameCards,
                    ...favoriteNHLGameCards,
                    ...favoriteMLBGameCards,
                ],
                search,
                filters
            );
        }, [
            favoriteNBAGameCards,
            favoriteWNBAGameCards,
            favoriteNHLGameCards,
            favoriteMLBGameCards,
            search,
            filters,
        ]);

    useEffect(() => {
        setFilters([]);
    }, [location]);

    return (
        <SportsContext.Provider
            value={{
                nbaGames: mappedNBAGames,
                wnbaGames: mappedWNBAGames,
                nhlGames: mappedNHLGames,
                mlbGames: mappedMLBGames,

                allOfTodaysGames,
                liveGames,

                nbaGamesLoading,
                wnbaGamesLoading,
                nhlGamesLoading,
                mlbGamesLoading,

                search,
                setSearch,

                filters,
                setFilters,
                addSportFilter,
                getGame,
                nbaGameCards,
                favoriteNBAGameCards,

                wnbaGameCards,
                favoriteWNBAGameCards,

                nhlGameCards,
                favoriteNHLGameCards,

                mlbGameCards,
                favoriteMLBGameCards,

                favoriteGameCards,

                layout,
                setLayout,
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