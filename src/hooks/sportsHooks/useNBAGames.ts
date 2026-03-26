import { useState } from "react"
import { useQuery } from "@tanstack/react-query";
import type { INBAGame } from "../../types/sports/nbaTypes";

interface UseNbaGames {
    nbaGames: INBAGame[];
    nbaGamesLoading: boolean;
    error: any;
    search: string;
    setSearch: React.Dispatch<React.SetStateAction<string>>;
}

export const useNBAGames = () : UseNbaGames => {
    const [search, setSearch] = useState("");

    const { data = [], isLoading, error } = useQuery({
        queryKey: ["nba-games"],
        queryFn: async () => {
            const API_URL = import.meta.env.VITE_API_URL || "";
            const res = await fetch(`${API_URL}/api/nba`);
            return res.json();
        },
        refetchInterval: 30000
    });
    console.log(data[0])
    return {
        nbaGames: data,
        nbaGamesLoading: isLoading,
        error,
        search,
        setSearch
    };
};