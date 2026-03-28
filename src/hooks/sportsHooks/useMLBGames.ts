import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import type { IMLBGame } from "../../types/sports/mlbTypes";

interface UseMLBGames {
    games: IMLBGame[];
    isLoading: boolean;
    error: any;
}

export const useMLBGames = (): UseMLBGames => {

    const { data = [], isLoading, error } = useQuery({
        queryKey: ["mlb-games"],
        queryFn: async () => {
            const API_URL = import.meta.env.VITE_API_URL || "";
            const res = await fetch(`${API_URL}/api/mlb`);
            return res.json();
        },
        refetchInterval: 30000
    });

    return {
        games: data,
        isLoading: isLoading,
        error,
    };
};