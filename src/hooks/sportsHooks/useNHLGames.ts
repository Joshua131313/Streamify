import { useQuery } from "@tanstack/react-query";
import type { NHLGame, ScheduleResponse } from "../../types/sports/nhlTypes";
import { extractGames } from "../../utils/sports/nhlUtils";
import { DateTime } from "luxon";

const fetchGames = async (): Promise<NHLGame[]> => {
    const API_URL = import.meta.env.VITE_API_URL || "";
    const res = await fetch(`${API_URL}/api/nhl`);

    if (!res.ok) throw new Error("Failed to fetch games");

    const data: ScheduleResponse = await res.json();
    console.log("data", data)
    return extractGames(data);
};

export const useNHLGames = () => {
    const {
        data: games = [],
        isLoading,
        error,
    } = useQuery({
        queryKey: ["nhl-games"],
        queryFn: fetchGames,

        staleTime: 1000 * 60 * 5,
        refetchInterval: 30000,
        refetchOnWindowFocus: false,
    });

    const todaysGames = games.filter(game =>
        DateTime.fromISO(game.startTimeUTC)
            .toLocal()
            .hasSame(DateTime.now(), "day")
    );

    return {
        games,
        todaysGames,
        isLoading,
        error,
    };
};