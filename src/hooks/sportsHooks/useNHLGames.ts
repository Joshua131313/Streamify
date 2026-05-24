import type { INHLGame } from "../../types/sports/nhlTypes";
import { useSportsQuery } from "./useSportsQuery";

export const useNHLGames = () => {

    const {
        data,
        isLoading,
        error,
    } = useSportsQuery<INHLGame>({
        queryKey: ["nhl-games"],
        endpoint: "/api/nhl",
    });

    return {
        games: data,
        isLoading,
        error,
    };
};