import type { INBAGame } from "../../types/sports/nbaTypes";
import { useSportsQuery } from "./useSportsQuery";

interface UseNbaGames {
    nbaGames: INBAGame[];
    nbaGamesLoading: boolean;
    error: any;
}

export const useNBAGames =
(): UseNbaGames => {

    const {
        data,
        isLoading,
        error,
    } = useSportsQuery<INBAGame>({
        queryKey: ["nba-games"],
        endpoint: "/api/nba",
    });

    return {
        nbaGames: data,
        nbaGamesLoading: isLoading,
        error,
    };
};