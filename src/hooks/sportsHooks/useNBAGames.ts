import { useState } from "react"
import { useQuery } from "@tanstack/react-query";
import type { INBAGame } from "../../types/sports/nbaTypes";

interface UseNbaGames {
    nbaGames: INBAGame[];
    nbaGamesLoading: boolean;
    error: any;
}

export const useNBAGames = () : UseNbaGames => {

    const { data = [], isLoading, error } = useQuery({
        queryKey: ["nba-games"],
        queryFn: async () => {
            const API_URL = import.meta.env.VITE_API_URL || "";
            const res = await fetch(`${API_URL}/api/nba`);
            return res.json();
        },
        refetchInterval: 30000
    });
    
    return {
        nbaGames: data,
        nbaGamesLoading: isLoading,
        error,
    };
};