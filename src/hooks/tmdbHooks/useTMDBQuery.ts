import axios from "axios";
import { useQuery } from "@tanstack/react-query";

interface TMDBQueryProps {
  endpoint: string;
  params?: Record<string, any>;
}

export const useTMDBQuery = <T = any>({
  endpoint,
  params = {},
}: TMDBQueryProps) => {
    
  return useQuery<T>({
    queryKey: ["tmdb", endpoint, params],
    queryFn: async () => {
      const res = await axios.get(
        `https://api.themoviedb.org/3${endpoint}`,
        {
          params: {
            api_key: import.meta.env.VITE_TMDB_API_KEY,
            ...params,
          },
        }
      );
      return res.data;
    },
  });
};
