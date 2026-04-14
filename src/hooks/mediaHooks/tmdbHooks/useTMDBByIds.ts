// hooks/tmdbHooks/useTMDBByIds.ts
import { useQueries } from "@tanstack/react-query";
import { useTMDBQuery } from "./useTMDBQuery";
import { normalizeMovie, normalizeShow } from "../../../utils/normalizeTMDB";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import type { TMediaType } from "../../../types/tmdb";


type Input = {
  mediaId: number;
  mediaType: TMediaType;
};

export const useTMDBByIds = (items: Input[]) => {
  const queries = useQueries({
    queries: items.map(item => ({
      queryKey: ["media", item.mediaType, item.mediaId],
      queryFn: async () => {
        const endpoint = `/${item.mediaType}/${item.mediaId}`;

        const res = await fetch(
          `https://api.themoviedb.org/3${endpoint}?api_key=${import.meta.env.VITE_TMDB_API_KEY}`
        );

        if (!res.ok) throw new Error("Failed");

        const data = await res.json();

        return item.mediaType === "movie"
          ? normalizeMovie(data)
          : normalizeShow(data);
      },
      staleTime: 1000 * 60 * 10,
    }))
  });

  const media: TMDBMedia[] = queries
    .map(q => q.data)
    .filter(Boolean) as TMDBMedia[];

  const isLoading = queries.some(q => q.isLoading);

  return { media, isLoading };
};