import { useEffect, useState } from "react"
import type { INBAGame } from "../../types/sports/nbaTypes";
import { useQuery } from "@tanstack/react-query";

// export const useNBAGames = () => {
//     const [games, setGames] = useState<INBAGame[]>([]);
//     const [search, setSearch] = useState("");
//     const [loading, setLoading] = useState(true);
//     const [error, setError] = useState(null);

//     useEffect(() => {
//         const fetchGames = async () => {
//             try {
//                 const API_URL = import.meta.env.VITE_API_URL || "";
//                 const response = await fetch(`${API_URL}/api/scrape`);
//                 if (!response.ok) {
//                     throw new Error("Failed to get games");
//                 }
//                 const data: INBAGame[] = await response.json();
//                 console.log('b', games)
//                 setGames(data)
//             }
//             catch (err: any) {
//                 setError(err.message);
//             }
//             finally {
//                 setLoading(false);
//             }
//         }
//         fetchGames();
//     }, [])

//     return {
//         nbaGames: games,
//         loading,
//         error,
//         search,
//         setSearch
//     }

// }

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