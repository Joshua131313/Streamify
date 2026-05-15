import type { INBAGame } from "../../types/sports/nbaTypes";
import type { INHLGame } from "../../types/sports/nhlTypes";
import type { IMLBGame } from "../../types/sports/mlbTypes";

import type {
    SportDisplayGame,
} from "../../types/sports/sportsDisplayTypes";

import { mapNBAToGameProps } from "./nbaUtils";
import { mapNHLToGameProps } from "./nhlUtils";
import { mapMLBToGameProps } from "./mlbUtils";

import { filterGames } from "./sportsUtils";

import type {
    SportFilter,
} from "../../context/SportsContext";

export const createNBADisplayGame = (
    game: INBAGame
): SportDisplayGame => {

    return {
        league: "NBA",
        id: game.id,
        raw: game,
        card: mapNBAToGameProps(game),
    };
};

export const createNHLDisplayGame = (
    game: INHLGame
): SportDisplayGame => {

    return {
        league: "NHL",
        id: game.id,
        raw: game,
        card: mapNHLToGameProps(game),
    };
};

export const createMLBDisplayGame = (
    game: IMLBGame
): SportDisplayGame => {

    return {
        league: "MLB",
        id: game.id,
        raw: game,
        card: mapMLBToGameProps(game),
    };
};

const STATUS_PRIORITY = {
    LIVE: 0,
    HALFTIME: 1,
    PRE: 2,
    FUT: 3,
    FINAL: 4,
} as const;

export const sortDisplayGames = (
    games: SportDisplayGame[]
): SportDisplayGame[] => {

    return [...games].sort((a, b) => {

        const aPriority =
            STATUS_PRIORITY[
                a.card.status
            ] ?? 999;

        const bPriority =
            STATUS_PRIORITY[
                b.card.status
            ] ?? 999;


        if (aPriority !== bPriority) {
            return aPriority - bPriority;
        }
        if (
            a.card.status === "LIVE" ||
            a.card.status === "HALFTIME"
        ) {

            const aPeriod =
                Number(a.raw?.period?.current) || 0;

            const bPeriod =
                Number(b.raw?.period?.current) || 0;

            return bPeriod - aPeriod;
        }

        const aDate =
            new Date(a.card.startTime).getTime();

        const bDate =
            new Date(b.card.startTime).getTime();

        return aDate - bDate;
    });
};

export const filterDisplayGames = (
    games: SportDisplayGame[],
    search: string,
    filters: SportFilter[]
): SportDisplayGame[] => {

    const filteredCards = filterGames(
        games.map(game => game.card),
        search,
        filters
    );

    const allowedIds = new Set(
        filteredCards.map(
            game =>
                `${game.leagueName}-${game.id}`
        )
    );

    const filteredGames =
        games.filter(game =>
            allowedIds.has(
                `${game.card.leagueName}-${game.card.id}`
            )
        );

    return sortDisplayGames(
        filteredGames
    );
};

export const isFavoriteDisplayGame = (
    game: SportDisplayGame,
    favoriteTeamNames: Set<string>
): boolean => {

    return (
        favoriteTeamNames.has(
            game.card.homeTeam.name
        ) ||

        favoriteTeamNames.has(
            game.card.awayTeam.name
        )
    );
};