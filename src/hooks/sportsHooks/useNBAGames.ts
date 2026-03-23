import { useState } from "react"
import { useQuery } from "@tanstack/react-query";

export const useNBAGames = () => {
    const [search, setSearch] = useState("");

    const { data = [], isLoading, error } = useQuery({
        queryKey: ["nba-games"],
        queryFn: async () => {
            const API_URL = import.meta.env.VITE_API_URL || "";
            const res = await fetch(`${API_URL}/api/scrape`);
            return res.json();
        },
        refetchInterval: 30000
    });
    return {
        nbaGames: data,
        nbaGamesLoading: isLoading,
        error,
        search,
        setSearch
    };
};