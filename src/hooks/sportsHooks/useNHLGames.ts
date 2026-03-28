import { useQuery } from "@tanstack/react-query";
import type { INHLGame } from "../../types/sports/nhlTypes";

interface UseNHLGames {
  games: INHLGame[];
  isLoading: boolean;
  error: any;
}

export const useNHLGames = (): UseNHLGames => {
  const { data = [], isLoading, error } = useQuery({
    queryKey: ["nhl-games"],
    queryFn: async () => {
      const API_URL = import.meta.env.VITE_API_URL || "";
      const res = await fetch(`${API_URL}/api/nhl`);

      if (!res.ok) throw new Error("Failed to fetch NHL games");

      return res.json();
    },
    refetchInterval: 30000,
  });

  return {
    games: data,
    isLoading: isLoading,
    error,
  };
};