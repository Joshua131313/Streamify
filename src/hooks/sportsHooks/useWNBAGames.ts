import { useState } from "react"
import { useQuery } from "@tanstack/react-query";
import type { INBAGame } from "../../types/sports/nbaTypes";

interface UseNbaGames {
    wnbaGames: INBAGame[];
    wnbaGamesLoading: boolean;
    error: any;
}

export const useWNBAGames = () : UseNbaGames => {

    const { data = [], isPending, error } = useQuery({
        queryKey: ["wnba-games"],
        queryFn: async () => {
            const API_URL = import.meta.env.VITE_API_URL || "";
            const res = await fetch(`${API_URL}/api/wnba`);
            return res.json();
        },
        refetchInterval: 30000
    });
    return {
        wnbaGames: Array.isArray(data) ? data : [],
        wnbaGamesLoading: isPending,
        error,
    };
};