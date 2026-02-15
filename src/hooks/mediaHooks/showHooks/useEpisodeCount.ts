import { useQuery } from "@tanstack/react-query";

interface Params {
  showId: number;
  seasonNumber: number;
}

interface SeasonResponse {
  episodes?: { air_date?: string }[];
}

export const useEpisodeCount = ({ showId, seasonNumber }: Params) => {
  return useQuery({
    queryKey: ["season", showId, seasonNumber],

    queryFn: async (): Promise<SeasonResponse> => {
      const res = await fetch(
        `https://api.themoviedb.org/3/tv/${showId}/season/${seasonNumber}?api_key=${
          import.meta.env.VITE_TMDB_API_KEY
        }`
      );

      if (!res.ok) throw new Error("Failed to fetch season");

      return res.json();
    },

    /**
     * Small safe cache.
     * We handle "forever cache" logic outside.
     */
    staleTime: 1000 * 60 * 5,
    gcTime: 1000 * 60 * 60 * 24,

    /**
     * Return ONLY episode count
     */
    select: (data) => data?.episodes?.length ?? 0,
  });
};
