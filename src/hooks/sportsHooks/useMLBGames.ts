import type { IMLBGame } from "../../types/sports/mlbTypes";
import { useSportsQuery } from "./useSportsQuery";

export const useMLBGames = () => {

    const {
        data,
        isLoading,
        error,
    } = useSportsQuery<IMLBGame>({
        queryKey: ["mlb-games"],
        endpoint: "/api/mlb",
    });

    return {
        games: data,
        isLoading,
        error,
    };
};