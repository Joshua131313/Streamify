import { useMemo } from "react";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery";
import { normalizeTMDBMedia } from "../../../utils/normalizeTMDB";

interface TMDBCombinedCreditsResponse {
  cast: any[];
  crew: any[];
}

export const usePersonCredits = (personId: string) => {

  const query = useTMDBQuery<TMDBCombinedCreditsResponse>({
    endpoint: `/person/${personId}/combined_credits`,
  });

  const media = useMemo((): TMDBMedia[] => {

    if (!query.data) return [];

    const combined = [
      ...query.data.cast,
      ...query.data.crew,
    ];

    combined.sort((a, b) => b.popularity - a.popularity);

    return normalizeTMDBMedia(combined);

  }, [query.data]);

  return {
    ...query,
    media,
  };
};