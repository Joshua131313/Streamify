import type { INBAGame } from "../../types/sports/nbaTypes";
import { useSportsQuery } from "./useSportsQuery";

export const useWNBAGames = () => {

    const {
        data,
        isLoading,
        error,
    } = useSportsQuery<INBAGame>({
        queryKey: ["wnba-games"],
        endpoint: "/api/wnba",
    });

    return {
        wnbaGames: data,
        wnbaGamesLoading: isLoading,
        error,
    };
};